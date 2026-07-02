/**
 * Batch staging-canary wave control-plane persistence (IP-18.5.1).
 *
 * Records an approved wave and selected wave items in the Confluendo control DB
 * only. It never calls providers and never writes to Vamo staging or production.
 */

import { Client, type QueryResult } from "pg";

import type { BatchStagingCanaryWaveApprovalPlan } from "./batch-staging-canary-wave-policy.js";

export interface BatchStagingCanaryWavePgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface ApproveBatchStagingCanaryWaveInput {
  connectionString?: string;
  client?: BatchStagingCanaryWavePgClientLike;
  projectKey: string;
  plan: BatchStagingCanaryWaveApprovalPlan;
  actor: { type: "operator" | "api"; id: string };
  now?: string;
}

export interface ApproveBatchStagingCanaryWaveResult {
  ok: true;
  batchPlanId: string;
  waveId: string;
  auditId: string | null;
  waveKey: string;
  unitKeys: string[];
  idempotentReplay: boolean;
}

interface ProjectRow extends Record<string, unknown> {
  id: string;
}

interface PlanRow extends Record<string, unknown> {
  id: string;
}

interface WaveRow extends Record<string, unknown> {
  id: string;
  waveKey: string;
}

interface WaveItemRow extends Record<string, unknown> {
  unitKey: string;
}

export async function approveBatchStagingCanaryWave(
  input: ApproveBatchStagingCanaryWaveInput
): Promise<ApproveBatchStagingCanaryWaveResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  const now = input.now ?? input.plan.approvedAt;

  try {
    await client.query("begin");
    await client.query("set local statement_timeout = '5s'");

    const project = await loadProject(client, input.projectKey);
    if (!project) {
      throw new Error(`Unknown ingestion project "${input.projectKey}".`);
    }

    const plan = await loadActivePlan(client, project.id, input.plan.planId, input.plan.targetKey);
    if (!plan) {
      throw new Error(`Active batch plan "${input.plan.planId}" was not found.`);
    }

    const existing = await client.query<WaveRow>(
      `
        select id::text as id, wave_key as "waveKey"
        from ingestion_platform.ingestion_batch_canary_waves
        where batch_plan_id = $1::bigint
          and wave_key = $2
      `,
      [plan.id, input.plan.waveKey]
    );

    if (existing.rows[0]) {
      const items = await client.query<WaveItemRow>(
        `
          select unit_key as "unitKey"
          from ingestion_platform.ingestion_batch_canary_wave_items
          where wave_id = $1::bigint
          order by run_order asc, unit_key asc
        `,
        [existing.rows[0].id]
      );
      await client.query("commit");
      return {
        ok: true,
        batchPlanId: plan.id,
        waveId: existing.rows[0].id,
        auditId: null,
        waveKey: existing.rows[0].waveKey,
        unitKeys: items.rows.map((row) => row.unitKey),
        idempotentReplay: true
      };
    }

    const wave = await client.query<WaveRow>(
      `
        insert into ingestion_platform.ingestion_batch_canary_waves (
          batch_plan_id,
          wave_key,
          target_key,
          target_environment,
          max_units,
          max_rows,
          audit_reason,
          actor_type,
          actor_id,
          status,
          summary,
          approved_at,
          approval_expires_at,
          created_at,
          updated_at
        )
        values (
          $1::bigint,
          $2,
          $3,
          $4,
          $5,
          $6,
          $7,
          $8,
          $9,
          'approved',
          $10::jsonb,
          $11::timestamptz,
          $12::timestamptz,
          $13::timestamptz,
          $13::timestamptz
        )
        returning id::text as id, wave_key as "waveKey"
      `,
      [
        plan.id,
        input.plan.waveKey,
        input.plan.targetKey,
        input.plan.targetEnvironment,
        input.plan.maxUnits,
        input.plan.maxRows,
        input.plan.auditReason,
        input.actor.type,
        input.actor.id,
        JSON.stringify({
          unitKeys: input.plan.unitKeys,
          totalPlannedRows: input.plan.totalPlannedRows,
          approvedBy: input.plan.approvedBy
        }),
        input.plan.approvedAt,
        input.plan.approvalExpiresAt,
        now
      ]
    );

    const waveId = wave.rows[0]?.id;
    const waveKey = wave.rows[0]?.waveKey;
    if (!waveId || !waveKey) {
      throw new Error("Failed to create batch staging-canary wave row.");
    }

    for (const unit of input.plan.selectedUnits) {
      const report = unit.dryRunReport;
      const writeCount = report ? report.insertCount + report.updateCount : 0;
      await client.query(
        `
          insert into ingestion_platform.ingestion_batch_canary_wave_items (
            wave_id,
            unit_key,
            run_order,
            status,
            planned_row_count,
            blockers,
            created_at,
            updated_at
          )
          values ($1::bigint, $2, $3, 'approved', $4, '[]'::jsonb, $5::timestamptz, $5::timestamptz)
        `,
        [waveId, unit.unitKey, unit.runOrder, writeCount, now]
      );
    }

    await client.query(
      `
        update ingestion_platform.ingestion_batch_queue_items
        set status = 'staging_canary_approved',
            updated_at = $3::timestamptz
        where batch_plan_id = $1::bigint
          and unit_key = any($2::text[])
          and status = 'dry_run_succeeded'
      `,
      [plan.id, input.plan.unitKeys, now]
    );

    const audit = await client.query<{ id: string }>(
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
        values (
          $1::bigint,
          $2,
          $3,
          'approve_batch_staging_canary_wave',
          'batch_canary_wave',
          $4,
          $5,
          $6::jsonb,
          $7::timestamptz
        )
        returning id::text as id
      `,
      [
        project.id,
        input.actor.type,
        input.actor.id,
        waveId,
        input.plan.auditReason,
        JSON.stringify({
          accepted: true,
          waveKey: input.plan.waveKey,
          plan: input.plan,
          unitKeys: input.plan.unitKeys
        }),
        now
      ]
    );

    await client.query("commit");

    return {
      ok: true,
      batchPlanId: plan.id,
      waveId,
      auditId: audit.rows[0]?.id ?? null,
      waveKey,
      unitKeys: input.plan.unitKeys,
      idempotentReplay: false
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    await closeClient(ownedClient);
  }
}

async function openClient(
  client?: BatchStagingCanaryWavePgClientLike,
  connectionString?: string
): Promise<{ client: BatchStagingCanaryWavePgClientLike; ownedClient?: Client }> {
  if (!client && !connectionString) {
    throw new Error("Batch staging-canary wave mutation requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Batch staging-canary wave client could not be initialized.");
  }
  if (ownedClient) {
    await ownedClient.connect();
  }
  return { client: resolved, ownedClient };
}

async function closeClient(client?: Client): Promise<void> {
  if (client) {
    await client.end();
  }
}

async function loadProject(
  client: BatchStagingCanaryWavePgClientLike,
  projectKey: string
): Promise<ProjectRow | undefined> {
  const result = await client.query<ProjectRow>(
    `
      select id::text as id
      from ingestion_platform.ingestion_projects
      where project_key = $1
    `,
    [projectKey]
  );
  return result.rows[0];
}

async function loadActivePlan(
  client: BatchStagingCanaryWavePgClientLike,
  projectId: string,
  planId: string,
  targetKey: string
): Promise<PlanRow | undefined> {
  const result = await client.query<PlanRow>(
    `
      select id::text as id
      from ingestion_platform.ingestion_batch_plans
      where project_id = $1::bigint
        and plan_key = $2
        and target_key = $3
        and status = 'active'
      limit 1
    `,
    [projectId, planId, targetKey]
  );
  return result.rows[0];
}
