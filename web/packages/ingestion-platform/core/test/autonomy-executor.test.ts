import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { sampleVamoEuPoiBatchYaml } from "../src/batch-plan-read-model.js";
import {
  buildBatchQueueSnapshotFromItems,
  sampleVamoEuPoiBatchQueueSnapshot,
  type BatchQueueItem,
  type BatchQueueItemStatus
} from "../src/batch-queue-read-model.js";
import { persistBatchQueueSnapshot } from "../src/batch-queue-control.js";
import {
  buildAutonomyRunKey,
  executeAutonomyCycle,
  previewAutonomyCycle
} from "../src/autonomy-executor.js";
import { evaluateAutonomyCycle } from "../src/autonomy-policy.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;
const agentId = "autonomy-executor-smoke";

describe("autonomy executor", () => {
  it("preview/evaluation writes nothing", { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL." }, async () => {
    const client = await setupDb();
    try {
      await seedPolicyAndQueue(client, { readyForDryRun: 2 });
      const beforeRuns = await countTable(client, "ingestion_autonomy_runs");
      const beforeEvents = await countTable(client, "ingestion_events");
      const preview = await previewAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId
      });
      assert.equal(preview.mode, "preview");
      assert.equal(preview.writes, false);
      assert.equal(await countTable(client, "ingestion_autonomy_runs"), beforeRuns);
      assert.equal(await countTable(client, "ingestion_events"), beforeEvents);
    } finally {
      await teardownDb(client);
    }
  });

  it("pause path records only an autonomy run without queue mutation", { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL." }, async () => {
    const client = await setupDb();
    try {
      await seedPolicyAndQueue(client, { blocked: true });
      const beforeReady = await countQueueStatus(client, "ready_for_dry_run");
      const result = await executeAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId,
        now: "2026-07-06T12:00:00.000Z"
      });
      assert.equal(result.runStatus, "paused");
      assert.equal(result.actionApplied, null);
      assert.equal(await countQueueStatus(client, "ready_for_dry_run"), beforeReady);
      assert.equal(await countTable(client, "ingestion_autonomy_runs"), 1);
      assert.ok(await countEvents(client, "autonomy.cycle.paused") >= 1);
    } finally {
      await teardownDb(client);
    }
  });

  it("schedule_dry_run records run, events, and schedules queue items", { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL." }, async () => {
    const client = await setupDb();
    try {
      await seedPolicyAndQueue(client, { readyForDryRun: 3 });
      const result = await executeAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId,
        now: "2026-07-06T12:10:00.000Z"
      });
      assert.equal(result.actionApplied, "schedule_dry_run");
      assert.equal(result.runStatus, "advanced");
      assert.equal(await countQueueStatus(client, "dry_run_ready"), 1);
      assert.ok(await countEvents(client, "autonomy.action.applied") >= 1);
      const run = await client.query<{ selected_units: string[] }>(
        `select selected_units from ingestion_platform.ingestion_autonomy_runs where run_key = $1`,
        [result.context.runKey]
      );
      assert.equal(run.rows[0]?.selected_units.length, 1);
    } finally {
      await teardownDb(client);
    }
  });

  it("execute_dry_run records run, events, and dry-run execution", { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL." }, async () => {
    const client = await setupDb();
    try {
      await seedPolicyAndQueue(client, { dryRunReady: 2 });
      const result = await executeAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId,
        now: "2026-07-06T12:20:00.000Z"
      });
      assert.equal(result.actionApplied, "execute_dry_run");
      assert.ok(result.dryRunExecutionKey);
      assert.equal(await countQueueStatus(client, "dry_run_succeeded"), 1);
      assert.equal(await countTable(client, "ingestion_batch_dry_run_executions"), 1);
    } finally {
      await teardownDb(client);
    }
  });

  it("marks an opened run failed when applying the action throws", { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL." }, async () => {
    const client = await setupDb();
    try {
      await seedPolicyAndQueue(client, { dryRunReady: 1 });
      await client.query("drop table ingestion_platform.ingestion_batch_dry_run_executions");

      await assert.rejects(
        () =>
          executeAutonomyCycle({
            client,
            projectKey: "vamo",
            policyKey: "vamo-eu-poi-staging-v1",
            agentId,
            now: "2026-07-06T12:25:00.000Z"
          }),
        /ingestion_batch_dry_run_executions|does not exist|relation/
      );

      const run = await client.query<{
        status: string;
        pause_reason: string | null;
        guard_outcome: Record<string, unknown>;
        corrective_actions: Record<string, unknown>[];
      }>(
        `
          select status, pause_reason, guard_outcome, corrective_actions
          from ingestion_platform.ingestion_autonomy_runs
        `
      );
      assert.equal(run.rows.length, 1);
      assert.equal(run.rows[0]?.status, "failed");
      assert.match(run.rows[0]?.pause_reason ?? "", /Autonomy action failed/);
      assert.equal(
        (run.rows[0]?.guard_outcome.actionError as { code?: string } | undefined)?.code,
        "42P01"
      );
      assert.equal(run.rows[0]?.corrective_actions.length, 1);

      const event = await client.query<{
        severity: string;
        payload: {
          evidence?: {
            actionError?: { code?: string };
            correctiveActions?: unknown[];
          };
        };
      }>(
        `
          select severity, payload
          from ingestion_platform.ingestion_events
          where event_type = 'autonomy.cycle.failed'
        `
      );
      assert.equal(event.rows.length, 1);
      assert.equal(event.rows[0]?.severity, "error");
      assert.equal(event.rows[0]?.payload.evidence?.actionError?.code, "42P01");
      assert.equal(event.rows[0]?.payload.evidence?.correctiveActions?.length, 1);
    } finally {
      await teardownDb(client);
    }
  });

  it("retries a failed run key after the operator fixes the underlying condition", { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL." }, async () => {
    const client = await setupDb();
    try {
      await seedPolicyAndQueue(client, { dryRunReady: 1 });
      const preview = await previewAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId,
        now: "2026-07-06T12:28:00.000Z"
      });
      const failedRunId = await insertFailedAutonomyRun(client, preview.context.runKey);

      const result = await executeAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId,
        now: "2026-07-06T12:29:00.000Z"
      });

      assert.equal(result.runId, failedRunId);
      assert.equal(result.idempotentReplay, false);
      assert.equal(result.runStatus, "advanced");
      assert.equal(result.actionApplied, "execute_dry_run");
      assert.equal(await countTable(client, "ingestion_autonomy_runs"), 1);
      assert.equal(await countTable(client, "ingestion_batch_dry_run_executions"), 1);

      const run = await client.query<{ status: string; dry_run_execution_key: string | null }>(
        `
          select status, dry_run_execution_key
          from ingestion_platform.ingestion_autonomy_runs
          where id = $1::bigint
        `,
        [failedRunId]
      );
      assert.equal(run.rows[0]?.status, "advanced");
      assert.ok(run.rows[0]?.dry_run_execution_key);
    } finally {
      await teardownDb(client);
    }
  });

  it("staging path approves a wave but does not execute live staging", { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL." }, async () => {
    const client = await setupDb();
    try {
      await seedPolicyAndQueue(client, { dryRunSucceeded: 1 });
      assert.equal(process.env.VAMO_STAGING_CANARY_APP_DATABASE_URL, undefined);
      const preview = await previewAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId
      });
      assert.equal(preview.context.evaluation.requiredAction, "approve_or_execute_staging_wave_later");
      const result = await executeAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId,
        now: "2026-07-06T12:30:00.000Z"
      });
      assert.equal(result.actionApplied, "approve_staging_wave");
      assert.ok(result.waveKey);
      assert.equal(await countTable(client, "ingestion_batch_canary_waves"), 1);
      assert.equal(await countTable(client, "ingestion_shipments"), 0);
      const wave = await client.query<{
        actor_type: string;
        actor_id: string;
        summary: {
          approvedBy?: {
            email?: string;
            role?: string;
            assuranceLevel?: string;
            policyApprovedBy?: string | null;
            policyApprovalAuditId?: string | null;
          };
        };
      }>(
        `
          select actor_type, actor_id, summary
          from ingestion_platform.ingestion_batch_canary_waves
        `
      );
      assert.equal(wave.rows[0]?.actor_type, "autonomous_agent");
      assert.equal(wave.rows[0]?.actor_id, agentId);
      assert.equal(wave.rows[0]?.summary.approvedBy?.email, agentId);
      assert.equal(wave.rows[0]?.summary.approvedBy?.role, "autonomous_agent");
      assert.equal(wave.rows[0]?.summary.approvedBy?.assuranceLevel, "policy");
      assert.equal(wave.rows[0]?.summary.approvedBy?.policyApprovedBy, "policy-owner@example.com");
      assert.equal(wave.rows[0]?.summary.approvedBy?.policyApprovalAuditId, "policy-audit-42");
    } finally {
      await teardownDb(client);
    }
  });

  it("refuses an oversized autonomous first wave before creating a wave", { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL." }, async () => {
    const client = await setupDb();
    try {
      await seedPolicyAndQueue(client, {
        dryRunSucceeded: 2,
        maxUnitsPerCycle: 2,
        maxRowsPerCycle: 4
      });

      await assert.rejects(
        () =>
          executeAutonomyCycle({
            client,
            projectKey: "vamo",
            policyKey: "vamo-eu-poi-staging-v1",
            agentId,
            now: "2026-07-06T12:35:00.000Z"
          }),
        /first-wave cap/
      );

      assert.equal(await countTable(client, "ingestion_batch_canary_waves"), 0);
      const run = await client.query<{ status: string; pause_reason: string | null }>(
        `select status, pause_reason from ingestion_platform.ingestion_autonomy_runs`
      );
      assert.equal(run.rows[0]?.status, "failed");
      assert.match(run.rows[0]?.pause_reason ?? "", /first-wave cap/);
    } finally {
      await teardownDb(client);
    }
  });

  it("refuses production inbox with waiting_for_ip18_6", () => {
    const evaluation = evaluateAutonomyCycle({
      policy: {
        policyId: "1",
        policyKey: "prod-policy",
        projectKey: "vamo",
        sourceKey: "fixture",
        targetKey: "vamo-place-intelligence",
        targetEnvironment: "staging",
        status: "active",
        allowedTiers: [],
        allowedGeographies: [],
        allowedCategories: [],
        allowedTransitions: ["deliver_production_inbox"],
        maxUnitsPerCycle: 1,
        maxRowsPerCycle: 2,
        rollingLimits: {},
        guardThresholds: {},
        productionInboxHandoffPolicy: {},
        policyVersion: 1
      },
      queueSnapshot: buildBatchQueueSnapshotFromItems({
        planId: "plan",
        projectKey: "vamo",
        targetKey: "vamo-place-intelligence",
        targetEnvironment: "staging",
        sourceKey: "fixture",
        safetyMode: "dry_run",
        items: [
          baseItem("unit-a", "production_ready")
        ]
      }),
      actor: { type: "autonomous_agent", id: agentId }
    });
    assert.equal(evaluation.requiredAction, "waiting_for_ip18_6");
    assert.equal(evaluation.decision, "pause");
  });

  it("idempotent replay does not duplicate run or action rows", { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL." }, async () => {
    const client = await setupDb();
    try {
      await seedPolicyAndQueue(client, { blocked: true });
      const now = "2026-07-06T12:40:00.000Z";
      const first = await executeAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId,
        now
      });
      const second = await executeAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId,
        now
      });
      assert.equal(first.context.runKey, second.context.runKey);
      assert.equal(second.idempotentReplay, true);
      assert.equal(await countTable(client, "ingestion_autonomy_runs"), 1);
      assert.equal(await countEvents(client, "autonomy.cycle.paused"), 1);
    } finally {
      await teardownDb(client);
    }
  });

  it("counts failed runs toward the rolling daily cycle limit", { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL." }, async () => {
    const client = await setupDb();
    try {
      await seedPolicyAndQueue(client, {
        readyForDryRun: 1,
        rollingLimits: { maxCyclesPerDay: 1 }
      });
      await insertFailedAutonomyRun(client);

      const preview = await previewAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId
      });

      assert.equal(preview.context.evaluation.decision, "pause");
      assert.equal(preview.context.evaluation.pauseReasonCode, "rolling_limit_exceeded");
    } finally {
      await teardownDb(client);
    }
  });

  it("respects policy bounds of 1 unit and 2 rows", { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL." }, async () => {
    const client = await setupDb();
    try {
      await seedPolicyAndQueue(client, { dryRunReady: 5, rowsProcessed: 1 });
      const result = await executeAutonomyCycle({
        client,
        projectKey: "vamo",
        policyKey: "vamo-eu-poi-staging-v1",
        agentId,
        now: "2026-07-06T12:50:00.000Z"
      });
      assert.equal(result.context.evaluation.maxUnitsApplied, 1);
      assert.ok(result.context.evaluation.maxRowsApplied <= 2);
      assert.equal(await countQueueStatus(client, "dry_run_succeeded"), 1);
    } finally {
      await teardownDb(client);
    }
  });

  it("never infers environment from target key text", () => {
    const evaluation = evaluateAutonomyCycle({
      policy: {
        policyId: "1",
        policyKey: "vamo-eu-poi-staging-v1",
        projectKey: "vamo",
        sourceKey: "fsq-os-places-sample",
        targetKey: "vamo-place-intelligence-staging",
        targetEnvironment: "staging",
        status: "active",
        allowedTiers: [],
        allowedGeographies: [],
        allowedCategories: [],
        allowedTransitions: ["execute_dry_run"],
        maxUnitsPerCycle: 1,
        maxRowsPerCycle: 2,
        rollingLimits: {},
        guardThresholds: {},
        productionInboxHandoffPolicy: {},
        policyVersion: 1
      },
      queueSnapshot: buildBatchQueueSnapshotFromItems({
        planId: "plan",
        projectKey: "vamo",
        targetKey: "vamo-place-intelligence-staging",
        targetEnvironment: "production",
        sourceKey: "fsq-os-places-sample",
        safetyMode: "dry_run",
        items: [baseItem("unit-a", "dry_run_ready")]
      }),
      actor: { type: "autonomous_agent", id: agentId }
    });
    assert.equal(evaluation.pauseReasonCode, "target_environment_mismatch");
  });

  it("buildAutonomyRunKey is stable for identical evaluation", () => {
    const policy = {
      policyId: "1",
      policyKey: "vamo-eu-poi-staging-v1",
      projectKey: "vamo",
      sourceKey: "fsq",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging" as const,
      status: "active" as const,
      allowedTiers: [],
      allowedGeographies: [],
      allowedCategories: [],
      allowedTransitions: ["schedule_dry_run"],
      maxUnitsPerCycle: 1,
      maxRowsPerCycle: 2,
      rollingLimits: {},
      guardThresholds: {},
      productionInboxHandoffPolicy: {},
      policyVersion: 1
    };
    const evaluation = {
      decision: "continue" as const,
      phase: "planning" as const,
      selectedUnitKeys: ["fr-paris-city"],
      maxUnitsApplied: 1,
      maxRowsApplied: 1,
      requiredAction: "schedule_dry_run" as const,
      scannedCount: 10,
      blockedCount: 0,
      skippedCount: 9,
      highestSafetyMode: "dry_run" as const,
      telemetry: { eventName: "autonomy.cycle.started" as const }
    };
    assert.equal(
      buildAutonomyRunKey(policy, evaluation),
      buildAutonomyRunKey(policy, evaluation)
    );
    assert.notEqual(
      buildAutonomyRunKey(policy, evaluation, "human_runbook"),
      buildAutonomyRunKey(policy, evaluation, "autonomy_cli")
    );
    const deferredEvaluation = {
      ...evaluation,
      phase: "staging_canary" as const,
      requiredAction: "approve_or_execute_staging_wave_later" as const,
      recommendedAction: {
        action: "approve_or_execute_staging_wave_later" as const,
        summary: "Wave approval waits for human runbook.",
        evidence: { waveKey: "wave-a", waveStatus: "approved" }
      }
    };
    const executedEvaluation = {
      ...deferredEvaluation,
      recommendedAction: {
        ...deferredEvaluation.recommendedAction,
        evidence: { waveKey: "wave-a", waveStatus: "succeeded" }
      }
    };
    assert.notEqual(
      buildAutonomyRunKey(policy, deferredEvaluation, "human_runbook"),
      buildAutonomyRunKey(policy, executedEvaluation, "autonomy_cli")
    );
  });
});

async function setupDb(): Promise<Client> {
  assert.ok(databaseUrl);
  const client = new Client({ connectionString: databaseUrl });
  await client.connect();
  await client.query("drop schema if exists ingestion_platform cascade");
  await client.query(controlSchemaSql);
  return client;
}

async function teardownDb(client: Client): Promise<void> {
  await client.query("drop schema if exists ingestion_platform cascade");
  await client.end();
}

async function seedPolicyAndQueue(
  client: Client,
  shape: {
    readyForDryRun?: number;
    dryRunReady?: number;
    dryRunSucceeded?: number;
    blocked?: boolean;
    rowsProcessed?: number;
    maxUnitsPerCycle?: number;
    maxRowsPerCycle?: number;
    rollingLimits?: Record<string, unknown>;
  }
): Promise<void> {
  const project = await client.query<{ id: string }>(
    `insert into ingestion_platform.ingestion_projects (project_key, display_name) values ('vamo', 'Vamo') returning id::text as id`
  );
  const projectId = project.rows[0]!.id;

  await client.query(
    `
      insert into ingestion_platform.ingestion_autonomy_policies (
        project_id, policy_key, source_key, target_key, target_environment, status,
        allowed_tiers, allowed_geographies, allowed_categories, allowed_transitions,
        max_units_per_cycle, max_rows_per_cycle, rolling_limits, policy_version, approved_by,
        approved_audit_id, approval_reason
      )
      values (
        $1::bigint,
        'vamo-eu-poi-staging-v1',
        'fsq-os-places-sample',
        'vamo-place-intelligence',
        'staging',
        'active',
        '["staging_canary"]'::jsonb,
        '[]'::jsonb,
        '[]'::jsonb,
        '["schedule_dry_run","execute_dry_run","approve_staging_wave"]'::jsonb,
        $2,
        $3,
        $4::jsonb,
        1,
        'policy-owner@example.com',
        'policy-audit-42',
        'autonomy executor smoke'
      )
    `,
    [
      projectId,
      shape.maxUnitsPerCycle ?? 1,
      shape.maxRowsPerCycle ?? 2,
      JSON.stringify(shape.rollingLimits ?? {})
    ]
  );

  const parsed = parseBatchPlanSpec(sampleVamoEuPoiBatchYaml());
  assert.equal(parsed.ok, true);
  if (!parsed.ok) throw new Error("sample parse failed");

  const baseSnapshot = sampleVamoEuPoiBatchQueueSnapshot();
  const items = baseSnapshot.items.map((item, index) => {
    let status: BatchQueueItemStatus = "planned";
    if (shape.blocked) {
      status = "blocked";
    } else if (index < (shape.readyForDryRun ?? 0)) {
      status = "ready_for_dry_run";
    } else if (index < (shape.readyForDryRun ?? 0) + (shape.dryRunReady ?? 0)) {
      status = "dry_run_ready";
    } else if (
      index <
      (shape.readyForDryRun ?? 0) + (shape.dryRunReady ?? 0) + (shape.dryRunSucceeded ?? 0)
    ) {
      status = "dry_run_succeeded";
    }
    return {
      ...item,
      sourceKey: "fsq-os-places-sample",
      status,
      blockReasons: shape.blocked ? ["fixture:blocked"] : item.blockReasons,
      dryRunReport:
        status === "dry_run_succeeded" || status === "dry_run_ready"
          ? {
              wroteToTarget: false as const,
              rowsProcessed: shape.rowsProcessed ?? 1,
              insertCount: 1,
              updateCount: 0,
              noOpCount: 0
            }
          : item.dryRunReport
    };
  });

  const snapshot = buildBatchQueueSnapshotFromItems({
    planId: baseSnapshot.planId,
    projectKey: baseSnapshot.projectKey,
    targetKey: baseSnapshot.targetKey,
    targetEnvironment: baseSnapshot.targetEnvironment,
    sourceKey: "fsq-os-places-sample",
    safetyMode: baseSnapshot.safetyMode,
    items
  });

  await persistBatchQueueSnapshot({
    client,
    projectKey: "vamo",
    snapshot,
    spec: parsed.spec,
    now: "2026-07-06T11:00:00.000Z"
  });

  if (shape.dryRunSucceeded) {
    await client.query(
      `
        update ingestion_platform.ingestion_batch_queue_items
        set run_report = jsonb_build_object(
          'wroteToTarget', false,
          'rowsProcessed', coalesce($1::int, 1),
          'insertCount', 1,
          'updateCount', 0,
          'noOpCount', 0
        )
        where status = 'dry_run_succeeded'
      `,
      [shape.rowsProcessed ?? 1]
    );
  }
}

async function insertFailedAutonomyRun(
  client: Client,
  runKey = "failed-cycle-for-rolling-limit"
): Promise<string> {
  const result = await client.query<{ id: string }>(
    `
      insert into ingestion_platform.ingestion_autonomy_runs (
        project_id,
        policy_id,
        run_key,
        phase,
        status,
        actor_type,
        actor_id,
        selected_units,
        scanned_count,
        highest_safety_mode,
        guard_outcome,
        started_at,
        completed_at
      )
      select
        p.id,
        ap.id,
        $2,
        'dry_run',
        'failed',
        'autonomous_agent',
        $1,
        '[]'::jsonb,
        0,
        'dry_run',
        '{}'::jsonb,
        now(),
        now()
      from ingestion_platform.ingestion_projects p
      join ingestion_platform.ingestion_autonomy_policies ap on ap.project_id = p.id
      where p.project_key = 'vamo'
        and ap.policy_key = 'vamo-eu-poi-staging-v1'
      returning id::text as id
    `,
    [agentId, runKey]
  );
  const id = result.rows[0]?.id;
  if (!id) {
    throw new Error("Failed autonomy run fixture was not inserted.");
  }
  return id;
}

function baseItem(unitKey: string, status: BatchQueueItemStatus): BatchQueueItem {
  return {
    unitKey,
    runOrder: 1,
    geography: "paris-fr",
    geographyKind: "city",
    country: "fr",
    category: "city",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    sourceKey: "fsq-os-places-sample",
    priority: 1,
    status,
    blockReasons: []
  };
}

async function countTable(client: Client, table: string): Promise<number> {
  const result = await client.query<{ count: string }>(
    `select count(*)::text as count from ingestion_platform.${table}`
  );
  return Number(result.rows[0]?.count ?? 0);
}

async function countQueueStatus(client: Client, status: string): Promise<number> {
  const result = await client.query<{ count: string }>(
    `select count(*)::text as count from ingestion_platform.ingestion_batch_queue_items where status = $1`,
    [status]
  );
  return Number(result.rows[0]?.count ?? 0);
}

async function countEvents(client: Client, eventType: string): Promise<number> {
  const result = await client.query<{ count: string }>(
    `select count(*)::text as count from ingestion_platform.ingestion_events where event_type = $1`,
    [eventType]
  );
  return Number(result.rows[0]?.count ?? 0);
}
