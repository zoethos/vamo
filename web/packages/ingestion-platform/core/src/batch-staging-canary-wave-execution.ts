/**
 * Batch staging-canary wave execution (IP-18.5.2).
 *
 * Executes approved wave items one at a time via applyPostgresStagingCanary,
 * records control-plane state, and stops on first failure. Never writes to
 * production and never bypasses the IP-16 staging adapter boundary.
 */

import { Client, type QueryResult } from "pg";

import type { ApplyPostgresStagingCanaryResult } from "../../adapters/target/src/postgres-staging-canary.js";
import type { TargetProjectSpec } from "../../spec/src/types.js";
import {
  buildBatchWaveUnitScope,
  filterCandidatesForWaveUnit,
  type BatchWaveUnitScope
} from "./batch-staging-canary-wave-candidates.js";
import type { BatchStagingCanaryWaveExecutionPlan } from "./batch-staging-canary-wave-execution-policy.js";
import { loadStagingCanaryWave } from "./batch-staging-canary-wave-load.js";
import { evaluateBatchStagingCanaryWaveExecution } from "./batch-staging-canary-wave-execution-policy.js";
import type { BatchQueueItem } from "./batch-queue-read-model.js";
import { loadBatchQueueSnapshot } from "./batch-queue-control-read.js";
import type { PipelineRunResult, StagedCandidate } from "./pipeline-runner.js";
import {
  recordStagingCanaryShipment,
  type StagingCanaryShipmentItemForLedger
} from "./staging-canary-control.js";

export interface BatchStagingCanaryWaveExecutionPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface BatchStagingCanaryWaveExecutionDeps {
  loadCandidates?: (input: {
    unit: BatchQueueItem;
    scope: BatchWaveUnitScope;
  }) => Promise<StagedCandidate[]>;
  applyUnit?: (input: {
    unitKey: string;
    scope: BatchWaveUnitScope;
    candidates: StagedCandidate[];
    target: TargetProjectSpec;
    stagingConnectionString: string;
    proveStaging: () => boolean | Promise<boolean>;
  }) => Promise<ApplyPostgresStagingCanaryResult>;
}

export interface ExecuteBatchStagingCanaryWaveInput {
  controlConnectionString?: string;
  stagingConnectionString?: string;
  controlClient?: BatchStagingCanaryWaveExecutionPgClientLike;
  projectKey: string;
  targetEnvironment: string;
  waveKey?: string;
  approvalAuditId?: string;
  maxUnits?: number;
  maxRows?: number;
  actor: { type: "operator" | "api"; id: string };
  reason: string;
  target: TargetProjectSpec;
  proveStaging: () => boolean | Promise<boolean>;
  deps?: BatchStagingCanaryWaveExecutionDeps;
  now?: string;
}

export interface ExecuteBatchStagingCanaryWaveUnitResult {
  unitKey: string;
  status: "succeeded" | "skipped" | "blocked";
  shipmentId?: string | null;
  shipmentKey?: string;
  blockCode?: string;
  blockMessage?: string;
}

export interface ExecuteBatchStagingCanaryWaveResult {
  ok: true;
  waveId: string;
  waveKey: string;
  waveStatus: string;
  executionAuditId: string | null;
  idempotentReplay: boolean;
  succeededCount: number;
  blockedCount: number;
  skippedCount: number;
  unitResults: ExecuteBatchStagingCanaryWaveUnitResult[];
  safetySummary: string[];
}

interface ShipmentRow extends Record<string, unknown> {
  id: string;
  status: string;
}

const DEFAULT_EXECUTION_SAFETY_SUMMARY = [
  "Per-unit applyPostgresStagingCanary only — no aggregate write path.",
  "Target DB must expose confluendo_guard.environment_sentinel value=staging.",
  "Stop-on-first-failure; skip already-succeeded wave items.",
  "No production writes. No live provider calls.",
  "Execute requires CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY=YES and VAMO_STAGING_DATABASE_URL."
] as const;

export async function executeBatchStagingCanaryWave(
  input: ExecuteBatchStagingCanaryWaveInput
): Promise<ExecuteBatchStagingCanaryWaveResult> {
  if (!input.stagingConnectionString?.trim()) {
    throw new Error("VAMO_STAGING_DATABASE_URL is required for wave execution.");
  }

  const controlClient = await openControlClient(input.controlClient, input.controlConnectionString);
  const now = input.now ?? new Date().toISOString();
  let inTransaction = false;
  const committedTargetWrites: Array<{
    unitKey: string;
    shipmentKey: string;
    counts: ApplyPostgresStagingCanaryResult & { ok: true };
  }> = [];

  try {
    const wave = await loadStagingCanaryWave({
      client: controlClient,
      projectKey: input.projectKey,
      waveKey: input.waveKey,
      approvalAuditId: input.approvalAuditId
    });

    if (wave) {
      const existingExecution = await findExistingExecutionAudit(controlClient, wave.id, now);
      if (existingExecution?.complete) {
        return {
          ...existingExecution.result,
          waveKey: existingExecution.result.waveKey || wave.waveKey,
          safetySummary: [...DEFAULT_EXECUTION_SAFETY_SUMMARY]
        };
      }
    }

    const decision = evaluateBatchStagingCanaryWaveExecution({
      projectKey: input.projectKey,
      targetEnvironment: input.targetEnvironment,
      wave,
      maxUnits: input.maxUnits,
      maxRows: input.maxRows,
      now
    });

    if (!decision.ok) {
      const message = decision.blocks.map((block) => block.message).join("; ");
      throw new Error(`Wave execution blocked: ${message}`);
    }

    const plan = decision.plan;
    const snapshot = await loadBatchQueueSnapshot({
      client: controlClient,
      projectKey: input.projectKey,
      targetKey: plan.targetKey
    });
    if (!snapshot) {
      throw new Error("Batch queue snapshot was not found for wave execution.");
    }

    await controlClient.query("begin");
    inTransaction = true;
    await controlClient.query("set local statement_timeout = '30s'");

    await controlClient.query(
      `
        update ingestion_platform.ingestion_batch_canary_waves
        set status = 'running',
            updated_at = $2::timestamptz
        where id = $1::bigint
          and status in ('approved', 'running', 'partial')
      `,
      [plan.waveId, now]
    );

    const unitResults: ExecuteBatchStagingCanaryWaveUnitResult[] = [];
    let succeededCount = 0;
    let blockedCount = 0;
    let skippedCount = 0;
    let stop = false;

    for (const unitPlan of plan.unitPlans) {
      if (unitPlan.status === "skip_succeeded") {
        unitResults.push({ unitKey: unitPlan.unitKey, status: "skipped" });
        skippedCount += 1;
        continue;
      }
      if (stop) {
        continue;
      }

      const queueItem = snapshot.items.find((item) => item.unitKey === unitPlan.unitKey);
      if (!queueItem) {
        await markUnitBlocked(controlClient, {
          waveItemId: unitPlan.waveItemId,
          batchPlanId: wave!.batchPlanId,
          unitKey: unitPlan.unitKey,
          blockCode: "queue_item_missing",
          blockMessage: "Queue item was not found for wave unit.",
          now
        });
        unitResults.push({
          unitKey: unitPlan.unitKey,
          status: "blocked",
          blockCode: "queue_item_missing",
          blockMessage: "Queue item was not found for wave unit."
        });
        blockedCount += 1;
        stop = true;
        continue;
      }

      const existingShipment = await findSucceededShipment(controlClient, input.projectKey, unitPlan.shipmentKey);
      if (existingShipment) {
        await markUnitSucceeded(controlClient, {
          waveItemId: unitPlan.waveItemId,
          batchPlanId: wave!.batchPlanId,
          unitKey: unitPlan.unitKey,
          shipmentId: existingShipment.id,
          now
        });
        unitResults.push({
          unitKey: unitPlan.unitKey,
          status: "skipped",
          shipmentId: existingShipment.id,
          shipmentKey: unitPlan.shipmentKey
        });
        skippedCount += 1;
        continue;
      }

      const scope = buildBatchWaveUnitScope(queueItem);
      if (!scope) {
        await markUnitBlocked(controlClient, {
          waveItemId: unitPlan.waveItemId,
          batchPlanId: wave!.batchPlanId,
          unitKey: unitPlan.unitKey,
          blockCode: "invalid_unit_scope",
          blockMessage: "Unit dry-run report is missing or invalid for staging execution.",
          now
        });
        unitResults.push({
          unitKey: unitPlan.unitKey,
          status: "blocked",
          blockCode: "invalid_unit_scope",
          blockMessage: "Unit dry-run report is missing or invalid for staging execution."
        });
        blockedCount += 1;
        stop = true;
        continue;
      }

      await controlClient.query(
        `
          update ingestion_platform.ingestion_batch_queue_items
          set status = 'staging_canary_running',
              updated_at = $3::timestamptz
          where batch_plan_id = $1::bigint
            and unit_key = $2
        `,
        [wave!.batchPlanId, unitPlan.unitKey, now]
      );
      await controlClient.query(
        `
          update ingestion_platform.ingestion_batch_canary_wave_items
          set status = 'running',
              updated_at = $2::timestamptz
          where id = $1::bigint
        `,
        [unitPlan.waveItemId, now]
      );

      const candidates = input.deps?.loadCandidates
        ? await input.deps.loadCandidates({ unit: queueItem, scope })
        : [];

      const applyResult = input.deps?.applyUnit
        ? await input.deps.applyUnit({
            unitKey: unitPlan.unitKey,
            scope,
            candidates,
            target: input.target,
            stagingConnectionString: input.stagingConnectionString,
            proveStaging: input.proveStaging
          })
        : await defaultApplyUnit({
            scope,
            candidates,
            target: input.target,
            stagingConnectionString: input.stagingConnectionString,
            proveStaging: input.proveStaging
          });

      if (!applyResult.ok) {
        await markUnitBlocked(controlClient, {
          waveItemId: unitPlan.waveItemId,
          batchPlanId: wave!.batchPlanId,
          unitKey: unitPlan.unitKey,
          blockCode: applyResult.code,
          blockMessage: applyResult.message,
          now
        });
        unitResults.push({
          unitKey: unitPlan.unitKey,
          status: "blocked",
          blockCode: applyResult.code,
          blockMessage: applyResult.message
        });
        blockedCount += 1;
        stop = true;
        continue;
      }

      committedTargetWrites.push({
        unitKey: unitPlan.unitKey,
        shipmentKey: unitPlan.shipmentKey,
        counts: applyResult
      });

      const shipment = await recordStagingCanaryShipment({
        client: controlClient,
        projectKey: input.projectKey,
        targetId: unitPlan.unitKey,
        targetAdapter: "postgres-staging-canary",
        approvalAuditId: `${plan.approvalAuditId ?? plan.waveId}:${unitPlan.unitKey}`,
        actor: input.actor,
        reason: input.reason,
        counts: applyResult.counts,
        items: applyResult.items.map(toLedgerItem),
        shipmentKey: unitPlan.shipmentKey,
        manageTransaction: false,
        now
      });

      await markUnitSucceeded(controlClient, {
        waveItemId: unitPlan.waveItemId,
        batchPlanId: wave!.batchPlanId,
        unitKey: unitPlan.unitKey,
        shipmentId: shipment.shipmentId,
        now
      });

      unitResults.push({
        unitKey: unitPlan.unitKey,
        status: "succeeded",
        shipmentId: shipment.shipmentId,
        shipmentKey: unitPlan.shipmentKey
      });
      succeededCount += 1;
    }

    const waveStatus = resolveWaveStatus(succeededCount, blockedCount, plan.unitPlans.length, skippedCount);
    const summary = {
      succeededCount,
      blockedCount,
      skippedCount,
      unitResults,
      executionFinishedAt: now
    };

    const audit = await controlClient.query<{ id: string }>(
      `
        insert into ingestion_platform.ingestion_audit_log (
          project_id,
          actor_type,
          actor_id,
          action,
          target_type,
          target_id,
          reason,
          payload,
          created_at
        )
        select
          p.id,
          $2,
          $3,
          'execute_batch_staging_canary_wave',
          'batch_canary_wave',
          $4,
          $5,
          $6::jsonb,
          $7::timestamptz
        from ingestion_platform.ingestion_projects p
        where p.project_key = $1
        returning id::text as id
      `,
      [
        input.projectKey,
        input.actor.type,
        input.actor.id,
        plan.waveId,
        input.reason,
        JSON.stringify({ plan, summary, waveStatus }),
        now
      ]
    );

    await controlClient.query(
      `
        update ingestion_platform.ingestion_batch_canary_waves
        set status = $2,
            summary = coalesce(summary, '{}'::jsonb) || $3::jsonb,
            updated_at = $4::timestamptz
        where id = $1::bigint
      `,
      [
        plan.waveId,
        waveStatus,
        JSON.stringify({
          ...summary,
          executionAuditId: audit.rows[0]?.id ?? null,
          lastExecutionAt: now
        }),
        now
      ]
    );

    await controlClient.query("commit");
    inTransaction = false;

    return {
      ok: true,
      waveId: plan.waveId,
      waveKey: plan.waveKey,
      waveStatus,
      executionAuditId: audit.rows[0]?.id ?? null,
      idempotentReplay: false,
      succeededCount,
      blockedCount,
      skippedCount,
      unitResults,
      safetySummary: plan.safetySummary
    };
  } catch (error) {
    if (inTransaction) {
      await controlClient.query("rollback");
    }
    if (committedTargetWrites.length > 0) {
      const details = committedTargetWrites
        .map(
          (write) =>
            `${write.unitKey} (${write.shipmentKey}, writes=${write.counts.counts.writeCount})`
        )
        .join("; ");
      throw new Error(
        `TARGET WRITE SUCCEEDED BUT CONTROL LEDGER FAILED. Do not rerun blindly; reconcile or roll back the staged rows first. Units: ${details}. Original error: ${error instanceof Error ? error.message : String(error)}`
      );
    }
    throw error;
  } finally {
    if (!input.controlClient && controlClient instanceof Client) {
      await controlClient.end();
    }
  }
}

async function defaultApplyUnit(input: {
  scope: BatchWaveUnitScope;
  candidates: StagedCandidate[];
  target: TargetProjectSpec;
  stagingConnectionString: string;
  proveStaging: () => boolean | Promise<boolean>;
}): Promise<ApplyPostgresStagingCanaryResult> {
  const { applyPostgresStagingCanary } = await import(
    "../../adapters/target/src/postgres-staging-canary.js"
  );
  return applyPostgresStagingCanary({
    connectionString: input.stagingConnectionString,
    target: input.target,
    candidates: input.candidates,
    maxRows: input.scope.maxRows,
    expectedWrite: input.scope.expectedWrite,
    proveStaging: input.proveStaging
  });
}

async function openControlClient(
  client?: BatchStagingCanaryWaveExecutionPgClientLike,
  connectionString?: string
): Promise<BatchStagingCanaryWaveExecutionPgClientLike> {
  if (client) {
    return client;
  }
  if (!connectionString) {
    throw new Error("INGESTION_CONTROL_DATABASE_URL is required.");
  }
  const owned = new Client({ connectionString });
  await owned.connect();
  return owned;
}

async function findSucceededShipment(
  client: BatchStagingCanaryWaveExecutionPgClientLike,
  projectKey: string,
  shipmentKey: string
): Promise<ShipmentRow | undefined> {
  const result = await client.query<ShipmentRow>(
    `
      select s.id::text as id, s.status
      from ingestion_platform.ingestion_shipments s
      join ingestion_platform.ingestion_projects p on p.id = s.project_id
      where p.project_key = $1
        and s.shipment_key = $2
        and s.status = 'succeeded'
      limit 1
    `,
    [projectKey, shipmentKey]
  );
  return result.rows[0];
}

async function markUnitSucceeded(
  client: BatchStagingCanaryWaveExecutionPgClientLike,
  input: {
    waveItemId: string;
    batchPlanId: string;
    unitKey: string;
    shipmentId: string;
    now: string;
  }
): Promise<void> {
  await client.query(
    `
      update ingestion_platform.ingestion_batch_canary_wave_items
      set status = 'succeeded',
          shipment_id = $2::bigint,
          blockers = '[]'::jsonb,
          updated_at = $3::timestamptz
      where id = $1::bigint
    `,
    [input.waveItemId, input.shipmentId, input.now]
  );
  await client.query(
    `
      update ingestion_platform.ingestion_batch_queue_items
      set status = 'staging_canary_succeeded',
          updated_at = $3::timestamptz
      where batch_plan_id = $1::bigint
        and unit_key = $2
    `,
    [input.batchPlanId, input.unitKey, input.now]
  );
}

async function markUnitBlocked(
  client: BatchStagingCanaryWaveExecutionPgClientLike,
  input: {
    waveItemId: string;
    batchPlanId: string;
    unitKey: string;
    blockCode: string;
    blockMessage: string;
    now: string;
  }
): Promise<void> {
  const blockers = [{ code: input.blockCode, message: input.blockMessage }];
  await client.query(
    `
      update ingestion_platform.ingestion_batch_canary_wave_items
      set status = 'blocked',
          blockers = $2::jsonb,
          updated_at = $3::timestamptz
      where id = $1::bigint
    `,
    [input.waveItemId, JSON.stringify(blockers), input.now]
  );
  await client.query(
    `
      update ingestion_platform.ingestion_batch_queue_items
      set status = 'staging_canary_blocked',
          blockers = $3::jsonb,
          updated_at = $4::timestamptz
      where batch_plan_id = $1::bigint
        and unit_key = $2
    `,
    [input.batchPlanId, input.unitKey, JSON.stringify([input.blockMessage]), input.now]
  );
}

function resolveWaveStatus(
  succeeded: number,
  blocked: number,
  totalPlans: number,
  skipped: number
): string {
  if (blocked > 0) {
    return succeeded > 0 || skipped > 0 ? "partial" : "failed";
  }
  if (succeeded + skipped >= totalPlans) {
    return "succeeded";
  }
  return "partial";
}

function toLedgerItem(item: {
  targetTable: string;
  operation: "insert" | "update" | "no_op";
  recordKey: string;
  idempotencyKey: string;
  keys: Record<string, unknown>;
  columns: string[];
  priorState: Record<string, unknown> | null;
}): StagingCanaryShipmentItemForLedger {
  return {
    targetTable: item.targetTable,
    operation: item.operation,
    recordKey: item.recordKey,
    idempotencyKey: item.idempotencyKey,
    keys: item.keys,
    columns: item.columns,
    priorState: item.priorState
  };
}

async function findExistingExecutionAudit(
  client: BatchStagingCanaryWaveExecutionPgClientLike,
  waveId: string,
  now: string
): Promise<{ complete: boolean; result: ExecuteBatchStagingCanaryWaveResult } | null> {
  const result = await client.query<{ id: string; payload: Record<string, unknown> | null }>(
    `
      select id::text as id, payload
      from ingestion_platform.ingestion_audit_log
      where target_type = 'batch_canary_wave'
        and target_id = $1
        and action = 'execute_batch_staging_canary_wave'
      order by created_at desc, id desc
      limit 1
    `,
    [waveId]
  );
  const row = result.rows[0];
  if (!row?.payload || typeof row.payload !== "object") {
    return null;
  }
  const payload = row.payload as Record<string, unknown>;
  const summary = (payload.summary ?? payload) as Record<string, unknown>;
  const waveStatus = String(payload.waveStatus ?? summary.waveStatus ?? "");
  if (!waveStatus || waveStatus === "running") {
    return null;
  }
  return {
    complete: true,
    result: {
      ok: true,
      waveId,
      waveKey: String((payload.plan as Record<string, unknown> | undefined)?.waveKey ?? ""),
      waveStatus,
      executionAuditId: row.id,
      idempotentReplay: true,
      succeededCount: Number(summary.succeededCount ?? 0),
      blockedCount: Number(summary.blockedCount ?? 0),
      skippedCount: Number(summary.skippedCount ?? 0),
      unitResults: Array.isArray(summary.unitResults)
        ? (summary.unitResults as ExecuteBatchStagingCanaryWaveUnitResult[])
        : [],
      safetySummary: []
    }
  };
}

export type { PipelineRunResult };

export async function defaultLoadWaveUnitCandidates(input: {
  unit: BatchQueueItem;
  scope: BatchWaveUnitScope;
  pipeline: import("../../spec/src/types.js").PipelineSpec;
  fixtureRoot: string;
  runPipeline: (input: {
    pipeline: import("../../spec/src/types.js").PipelineSpec;
    batchSize: number;
    fixtureRoot: string;
  }) => Promise<PipelineRunResult>;
}): Promise<StagedCandidate[]> {
  const run = await input.runPipeline({
    pipeline: input.pipeline,
    batchSize: Math.max(input.scope.maxRows, 1),
    fixtureRoot: input.fixtureRoot
  });
  return filterCandidatesForWaveUnit(run.candidates, input.scope);
}
