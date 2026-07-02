/**
 * Load persisted staging-canary wave state from the Confluendo control DB.
 */

import { Client, type QueryResult } from "pg";

export interface BatchStagingCanaryWaveLoadPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface LoadedStagingCanaryWaveItem {
  id: string;
  unitKey: string;
  runOrder: number;
  status: string;
  plannedRowCount: number;
  blockers: string[];
  shipmentId: string | null;
}

export interface LoadedStagingCanaryWave {
  id: string;
  waveKey: string;
  batchPlanId: string;
  planKey: string;
  targetKey: string;
  targetEnvironment: string;
  maxUnits: number;
  maxRows: number;
  status: string;
  auditReason: string;
  approvalAuditId: string | null;
  approvedAt: string;
  approvalExpiresAt: string;
  summary: Record<string, unknown>;
  items: LoadedStagingCanaryWaveItem[];
}

export interface LoadStagingCanaryWaveInput {
  connectionString?: string;
  client?: BatchStagingCanaryWaveLoadPgClientLike;
  projectKey: string;
  waveKey?: string;
  approvalAuditId?: string;
}

interface WaveRow extends Record<string, unknown> {
  id: string;
  waveKey: string;
  batchPlanId: string;
  planKey: string;
  targetKey: string;
  targetEnvironment: string;
  maxUnits: number;
  maxRows: number;
  status: string;
  auditReason: string;
  approvedAt: string | Date;
  approvalExpiresAt: string | Date;
  summary: Record<string, unknown> | null;
  approvalAuditId: string | null;
}

interface ItemRow extends Record<string, unknown> {
  id: string;
  unitKey: string;
  runOrder: number;
  status: string;
  plannedRowCount: number;
  blockers: unknown;
  shipmentId: string | null;
}

export async function loadStagingCanaryWave(
  input: LoadStagingCanaryWaveInput
): Promise<LoadedStagingCanaryWave | null> {
  if (!input.client && !input.connectionString) {
    throw new Error("Staging-canary wave load requires a server-side connection string or client.");
  }
  if (!input.waveKey?.trim() && !input.approvalAuditId?.trim()) {
    throw new Error("Either waveKey or approvalAuditId is required.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Staging-canary wave load client could not be initialized.");
  }
  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    const values: unknown[] = [input.projectKey];
    let filter = "";
    if (input.waveKey?.trim()) {
      filter = "and w.wave_key = $2";
      values.push(input.waveKey.trim());
    } else {
      filter = "and a.id = $2::bigint";
      values.push(input.approvalAuditId!.trim());
    }

    const waveResult = await client.query<WaveRow>(
      `
        select
          w.id::text as id,
          w.wave_key as "waveKey",
          w.batch_plan_id::text as "batchPlanId",
          bp.plan_key as "planKey",
          w.target_key as "targetKey",
          w.target_environment as "targetEnvironment",
          w.max_units as "maxUnits",
          w.max_rows as "maxRows",
          w.status,
          w.audit_reason as "auditReason",
          w.approved_at as "approvedAt",
          w.approval_expires_at as "approvalExpiresAt",
          w.summary,
          coalesce(w.summary->>'approvalAuditId', a.id::text) as "approvalAuditId"
        from ingestion_platform.ingestion_batch_canary_waves w
        join ingestion_platform.ingestion_batch_plans bp on bp.id = w.batch_plan_id
        join ingestion_platform.ingestion_projects p on p.id = bp.project_id
        left join lateral (
          select id
          from ingestion_platform.ingestion_audit_log
          where target_type = 'batch_canary_wave'
            and target_id = w.id::text
            and action = 'approve_batch_staging_canary_wave'
          order by created_at desc, id desc
          limit 1
        ) a on true
        where p.project_key = $1
          ${filter}
        order by w.updated_at desc, w.id desc
        limit 1
      `,
      values
    );

    const wave = waveResult.rows[0];
    if (!wave) {
      return null;
    }

    const items = await client.query<ItemRow>(
      `
        select
          id::text as id,
          unit_key as "unitKey",
          run_order as "runOrder",
          status,
          planned_row_count as "plannedRowCount",
          blockers,
          shipment_id::text as "shipmentId"
        from ingestion_platform.ingestion_batch_canary_wave_items
        where wave_id = $1::bigint
        order by run_order asc, unit_key asc
      `,
      [wave.id]
    );

    return {
      id: wave.id,
      waveKey: wave.waveKey,
      batchPlanId: wave.batchPlanId,
      planKey: wave.planKey,
      targetKey: wave.targetKey,
      targetEnvironment: wave.targetEnvironment,
      maxUnits: wave.maxUnits,
      maxRows: wave.maxRows,
      status: wave.status,
      auditReason: wave.auditReason,
      approvalAuditId: wave.approvalAuditId,
      approvedAt: toIsoString(wave.approvedAt) ?? "",
      approvalExpiresAt: toIsoString(wave.approvalExpiresAt) ?? "",
      summary: wave.summary ?? {},
      items: items.rows.map((row) => ({
        id: row.id,
        unitKey: row.unitKey,
        runOrder: row.runOrder,
        status: row.status,
        plannedRowCount: row.plannedRowCount,
        blockers: Array.isArray(row.blockers) ? row.blockers.map(String) : [],
        shipmentId: row.shipmentId
      }))
    };
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

function toIsoString(value: string | Date | null | undefined): string | undefined {
  if (value instanceof Date) {
    return value.toISOString();
  }
  return typeof value === "string" ? value : undefined;
}
