/**
 * Production package-wave control-plane persistence (IP-18.6.1).
 *
 * Records an approved package wave and selected wave items in the Confluendo
 * control DB only. No provider calls and no production inbox delivery.
 */

import { Client, type QueryResult } from "pg";

import type { BatchControlActor } from "./batch-control-actor.js";
import type { BatchProductionPackageWaveApprovalPlan } from "./batch-production-package-wave-policy.js";

export interface BatchProductionPackageWavePgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface ApproveBatchProductionPackageWaveInput {
  connectionString?: string;
  client?: BatchProductionPackageWavePgClientLike;
  projectKey: string;
  plan: BatchProductionPackageWaveApprovalPlan;
  approvalAuditId: string;
  actor: BatchControlActor;
  now?: string;
}

export interface ApproveBatchProductionPackageWaveResult {
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

interface QueueItemRow extends Record<string, unknown> {
  id: string;
  unitKey: string;
}

export async function approveBatchProductionPackageWave(
  input: ApproveBatchProductionPackageWaveInput
): Promise<ApproveBatchProductionPackageWaveResult> {
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
        from ingestion_platform.ingestion_batch_production_package_waves
        where batch_plan_id = $1::bigint
          and wave_key = $2
      `,
      [plan.id, input.plan.waveKey]
    );

    if (existing.rows[0]) {
      const items = await client.query<{ unitKey: string }>(
        `
          select unit_key as "unitKey"
          from ingestion_platform.ingestion_batch_production_package_wave_items
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
        auditId: input.approvalAuditId,
        waveKey: existing.rows[0].waveKey,
        unitKeys: items.rows.map((row) => row.unitKey),
        idempotentReplay: true
      };
    }

    const wave = await client.query<WaveRow>(
      `
        insert into ingestion_platform.ingestion_batch_production_package_waves (
          project_id,
          batch_plan_id,
          wave_key,
          target_key,
          target_environment,
          schema_contract,
          max_units,
          max_rows,
          max_packages,
          approval_audit_id,
          approval_reason,
          approved_by,
          approved_at,
          approval_expires_at,
          actor_type,
          actor_id,
          status,
          summary,
          blockers,
          created_at,
          updated_at
        )
        values (
          $1::bigint,
          $2::bigint,
          $3,
          $4,
          $5,
          $6,
          $7,
          $8,
          $9,
          $10,
          $11,
          $12::jsonb,
          $13::timestamptz,
          $14::timestamptz,
          $15,
          $16,
          'approved',
          $17::jsonb,
          '[]'::jsonb,
          $18::timestamptz,
          $18::timestamptz
        )
        returning id::text as id, wave_key as "waveKey"
      `,
      [
        project.id,
        plan.id,
        input.plan.waveKey,
        input.plan.targetKey,
        input.plan.targetEnvironment,
        input.plan.schemaContract,
        input.plan.maxUnits,
        input.plan.maxRows,
        input.plan.maxPackages,
        input.approvalAuditId,
        input.plan.auditReason,
        JSON.stringify(input.plan.approvedBy),
        input.plan.approvedAt,
        input.plan.approvalExpiresAt,
        input.actor.type,
        input.actor.id,
        JSON.stringify({
          unitKeys: input.plan.unitKeys,
          totalPlannedRows: input.plan.totalPlannedRows,
          approvalAuditId: input.approvalAuditId
        }),
        now
      ]
    );

    const waveId = wave.rows[0]?.id;
    const waveKey = wave.rows[0]?.waveKey;
    if (!waveId || !waveKey) {
      throw new Error("Failed to create production package wave row.");
    }

    for (const selected of input.plan.selectedUnits) {
      const queueItem = await client.query<QueueItemRow>(
        `
          select id::text as id, unit_key as "unitKey"
          from ingestion_platform.ingestion_batch_queue_items
          where batch_plan_id = $1::bigint
            and unit_key = $2
        `,
        [plan.id, selected.item.unitKey]
      );
      const queueItemId = queueItem.rows[0]?.id;
      if (!queueItemId) {
        throw new Error(`Queue item "${selected.item.unitKey}" was not found.`);
      }

      await client.query(
        `
          insert into ingestion_platform.ingestion_batch_production_package_wave_items (
            wave_id,
            queue_item_id,
            unit_key,
            run_order,
            planned_row_count,
            schema_contract,
            package_key,
            dry_run_evidence,
            staging_evidence,
            status,
            blockers,
            created_at,
            updated_at
          )
          values (
            $1::bigint,
            $2::bigint,
            $3,
            $4,
            $5,
            $6,
            $7,
            $8::jsonb,
            $9::jsonb,
            'approved',
            '[]'::jsonb,
            $10::timestamptz,
            $10::timestamptz
          )
        `,
        [
          waveId,
          queueItemId,
          selected.item.unitKey,
          selected.item.runOrder,
          selected.writeCount,
          input.plan.schemaContract,
          selected.plannedPackageKey,
          JSON.stringify(selected.dryRunEvidence),
          JSON.stringify(selected.stagingEvidence),
          now
        ]
      );
    }

    const claimedUnits = await client.query(
      `
        update ingestion_platform.ingestion_batch_queue_items
        set status = 'production_package_approved',
            updated_at = $3::timestamptz
        where batch_plan_id = $1::bigint
          and unit_key = any($2::text[])
          and status = 'staging_canary_succeeded'
      `,
      [plan.id, input.plan.unitKeys, now]
    );
    if (claimedUnits.rowCount !== input.plan.unitKeys.length) {
      throw new Error(
        `Production package-wave approval could not claim all selected units (${claimedUnits.rowCount ?? 0}/${input.plan.unitKeys.length}).`
      );
    }

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
          'approve_batch_production_package_wave',
          'batch_production_package_wave',
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
          unitKeys: input.plan.unitKeys,
          approvalAuditId: input.approvalAuditId
        }),
        now
      ]
    );

    const auditId = audit.rows[0]?.id ?? input.approvalAuditId;
    await client.query(
      `
        update ingestion_platform.ingestion_batch_production_package_waves
        set approval_audit_id = $2,
            summary = coalesce(summary, '{}'::jsonb) || $3::jsonb,
            updated_at = $4::timestamptz
        where id = $1::bigint
      `,
      [
        waveId,
        auditId,
        JSON.stringify({ approvalAuditId: auditId, totalPlannedRows: input.plan.totalPlannedRows }),
        now
      ]
    );

    await client.query("commit");

    return {
      ok: true,
      batchPlanId: plan.id,
      waveId,
      auditId,
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
  client?: BatchProductionPackageWavePgClientLike,
  connectionString?: string
): Promise<{ client: BatchProductionPackageWavePgClientLike; ownedClient?: Client }> {
  if (!client && !connectionString) {
    throw new Error("Production package-wave mutation requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Production package-wave client could not be initialized.");
  }
  if (ownedClient) {
    await ownedClient.connect();
  }
  return { client: resolved, ownedClient };
}

async function closeClient(ownedClient?: Client): Promise<void> {
  if (ownedClient) {
    await ownedClient.end();
  }
}

async function loadProject(
  client: BatchProductionPackageWavePgClientLike,
  projectKey: string
): Promise<ProjectRow | null> {
  const result = await client.query<ProjectRow>(
    `
      select id::text as id
      from ingestion_platform.ingestion_projects
      where project_key = $1
    `,
    [projectKey]
  );
  return result.rows[0] ?? null;
}

async function loadActivePlan(
  client: BatchProductionPackageWavePgClientLike,
  projectId: string,
  planKey: string,
  targetKey: string
): Promise<PlanRow | null> {
  const result = await client.query<PlanRow>(
    `
      select id::text as id
      from ingestion_platform.ingestion_batch_plans
      where project_id = $1::bigint
        and plan_key = $2
        and target_key = $3
        and status = 'active'
      order by updated_at desc, id desc
      limit 1
    `,
    [projectId, planKey, targetKey]
  );
  return result.rows[0] ?? null;
}
