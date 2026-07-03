import { Client, type QueryResult } from "pg";

import {
  mapPersistenceBundleToSnapshot,
  type PersistedBatchPlanRow,
  type PersistedBatchQueueItemRow
} from "./batch-queue-persistence.js";
import type {
  BatchQueueItemStatus,
  BatchQueueLatestExecution,
  BatchQueueLatestWave,
  BatchQueueSnapshot
} from "./batch-queue-read-model.js";
import { formatBatchQueueBlockers } from "./batch-queue-read-model.js";

/**
 * Live read of persisted batch queue state into `BatchQueueSnapshot`.
 * Read-path only — never schedules, executes, or mutates queue rows.
 */

export interface BatchQueueControlReadPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface LoadBatchQueueSnapshotInput {
  connectionString?: string;
  client?: BatchQueueControlReadPgClientLike;
  projectKey: string;
  targetKey?: string;
}

interface PlanRow extends Record<string, unknown> {
  projectKey: string;
  planKey: string;
  sourceKey: string;
  targetKey: string;
  targetEnvironment: string;
  safetyMode: string;
  spec: Record<string, unknown>;
  planSummary: PersistedBatchPlanRow["planSummary"];
  status: string;
}

interface ItemRow extends Record<string, unknown> {
  unitKey: string;
  countryCode: string;
  geographyKey: string;
  geographyLabel: string | null;
  geographyKind: string;
  category: string;
  sourceKey: string;
  targetKey: string;
  targetEnvironment: string;
  status: string;
  priority: number;
  runOrder: number;
  blockers: string[];
  proposal: Record<string, unknown> | null;
  runReport: Record<string, unknown> | null;
}

interface WaveRow extends Record<string, unknown> {
  id: string;
  waveKey: string;
  status: string;
  targetEnvironment: string;
  maxUnits: number;
  maxRows: number;
  summary: Record<string, unknown> | null;
  approvedAt: string | Date;
  approvalExpiresAt: string | Date;
}

interface WaveItemRow extends Record<string, unknown> {
  unitKey: string;
  runOrder: number;
  status: string;
  plannedRowCount: number;
  blockers: unknown;
  shipmentId: string | null;
}

interface ExecutionRow extends Record<string, unknown> {
  executionKey: string;
  status: string;
  auditId: string | null;
  summary: Record<string, unknown> | null;
  finishedAt: string | Date | null;
}

interface WaveItemCountRow extends Record<string, unknown> {
  count: string;
}

const UNDEFINED_TABLE = "42P01";

export async function loadBatchQueueSnapshot(
  input: LoadBatchQueueSnapshotInput
): Promise<BatchQueueSnapshot | null> {
  if (!input.client && !input.connectionString) {
    throw new Error("Batch queue control read requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Batch queue control read client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    const planValues: unknown[] = [input.projectKey];
    let targetFilter = "";
    if (input.targetKey) {
      targetFilter = "and bp.target_key = $2";
      planValues.push(input.targetKey);
    }

    const planResult = await client.query<PlanRow>(
      `
        select
          p.project_key as "projectKey",
          bp.plan_key as "planKey",
          bp.source_key as "sourceKey",
          bp.target_key as "targetKey",
          bp.target_environment as "targetEnvironment",
          bp.safety_mode as "safetyMode",
          bp.spec as spec,
          bp.plan_summary as "planSummary",
          bp.status as status
        from ingestion_platform.ingestion_batch_plans bp
        join ingestion_platform.ingestion_projects p on p.id = bp.project_id
        where p.project_key = $1
          and bp.status = 'active'
          ${targetFilter}
        order by bp.updated_at desc, bp.id desc
        limit 1
      `,
      planValues
    );

    if (planResult.rows.length === 0) {
      return null;
    }

    const plan = planResult.rows[0]!;
    const planIdResult = await client.query<{ id: string }>(
      `
        select bp.id::text as id
        from ingestion_platform.ingestion_batch_plans bp
        join ingestion_platform.ingestion_projects p on p.id = bp.project_id
        where p.project_key = $1
          and bp.plan_key = $2
      `,
      [input.projectKey, plan.planKey]
    );
    const batchPlanId = planIdResult.rows[0]?.id;
    if (!batchPlanId) {
      return null;
    }

    const itemResult = await client.query<ItemRow>(
      `
        select
          unit_key as "unitKey",
          country_code as "countryCode",
          geography_key as "geographyKey",
          geography_label as "geographyLabel",
          geography_kind as "geographyKind",
          category,
          source_key as "sourceKey",
          target_key as "targetKey",
          target_environment as "targetEnvironment",
          status,
          priority,
          run_order as "runOrder",
          blockers,
          proposal,
          run_report as "runReport"
        from ingestion_platform.ingestion_batch_queue_items
        where batch_plan_id = $1
        order by run_order asc, unit_key asc
      `,
      [batchPlanId]
    );

    if (itemResult.rows.length === 0) {
      return null;
    }

    const latestExecution = await loadLatestExecution(client, batchPlanId);
    const latestWave = await loadLatestWave(client, batchPlanId);

    return mapPersistenceBundleToSnapshot(
      plan.projectKey,
      {
        planKey: plan.planKey,
        sourceKey: plan.sourceKey,
        targetKey: plan.targetKey,
        targetEnvironment: plan.targetEnvironment as "staging" | "production",
        safetyMode: plan.safetyMode,
        spec: plan.spec,
        planSummary: plan.planSummary,
        status: plan.status as "active" | "archived"
      },
      itemResult.rows.map((row) => ({
        unitKey: row.unitKey,
        countryCode: row.countryCode,
        geographyKey: row.geographyKey,
        geographyLabel: row.geographyLabel,
        geographyKind: row.geographyKind,
        category: row.category,
        sourceKey: row.sourceKey,
        targetKey: row.targetKey,
        targetEnvironment: row.targetEnvironment as "staging" | "production",
        status: row.status as BatchQueueItemStatus,
        priority: row.priority,
        runOrder: row.runOrder,
        blockers: formatBatchQueueBlockers(row.blockers),
        proposal: row.proposal,
        runReport: row.runReport
      })),
      latestExecution,
      latestWave
    );
  } catch (error) {
    if (isUndefinedTable(error)) {
      return null;
    }
    throw error;
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

function isUndefinedTable(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === UNDEFINED_TABLE;
}

async function loadLatestExecution(
  client: BatchQueueControlReadPgClientLike,
  batchPlanId: string
): Promise<BatchQueueLatestExecution | null> {
  try {
    const result = await client.query<ExecutionRow>(
      `
        select
          execution_key as "executionKey",
          status,
          audit_id as "auditId",
          summary,
          finished_at as "finishedAt"
        from ingestion_platform.ingestion_batch_dry_run_executions
        where batch_plan_id = $1::bigint
        order by updated_at desc, id desc
        limit 1
      `,
      [batchPlanId]
    );
    const row = result.rows[0];
    if (!row) {
      return null;
    }
    const summary = row.summary ?? {};
    return {
      executionKey: row.executionKey,
      status: row.status,
      auditId: row.auditId ?? undefined,
      succeededCount: Number(summary.succeededCount ?? 0),
      blockedCount: Number(summary.blockedCount ?? 0),
      runningCount: Number(summary.runningCount ?? 0),
      finishedAt:
        row.finishedAt instanceof Date
          ? row.finishedAt.toISOString()
          : typeof row.finishedAt === "string"
            ? row.finishedAt
            : undefined
    };
  } catch (error) {
    if (isUndefinedTable(error)) {
      return null;
    }
    throw error;
  }
}

async function loadLatestWave(
  client: BatchQueueControlReadPgClientLike,
  batchPlanId: string
): Promise<BatchQueueLatestWave | null> {
  try {
    const result = await client.query<WaveRow>(
      `
        select
          id::text as id,
          wave_key as "waveKey",
          status,
          target_environment as "targetEnvironment",
          max_units as "maxUnits",
          max_rows as "maxRows",
          summary,
          approved_at as "approvedAt",
          approval_expires_at as "approvalExpiresAt"
        from ingestion_platform.ingestion_batch_canary_waves
        where batch_plan_id = $1::bigint
        order by updated_at desc, id desc
        limit 1
      `,
      [batchPlanId]
    );
    const row = result.rows[0];
    if (!row) {
      return null;
    }

    const itemCount = await client.query<WaveItemCountRow>(
      `
        select count(*)::text as count
        from ingestion_platform.ingestion_batch_canary_wave_items wi
        join ingestion_platform.ingestion_batch_canary_waves w on w.id = wi.wave_id
        where w.batch_plan_id = $1::bigint
          and w.wave_key = $2
      `,
      [batchPlanId, row.waveKey]
    );

    const waveItems = await client.query<WaveItemRow>(
      `
        select
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
      [row.id]
    );

    const summary = row.summary ?? {};
    return {
      waveKey: row.waveKey,
      status: row.status,
      targetEnvironment: row.targetEnvironment,
      maxUnits: row.maxUnits,
      maxRows: row.maxRows,
      unitCount: Number.parseInt(itemCount.rows[0]?.count ?? "0", 10),
      totalPlannedRows: Number(summary.totalPlannedRows ?? 0),
      approvalAuditId:
        typeof summary.approvalAuditId === "string" ? summary.approvalAuditId : null,
      executionAuditId:
        typeof summary.executionAuditId === "string" ? summary.executionAuditId : null,
      approvedAt: toIsoString(row.approvedAt),
      approvalExpiresAt: toIsoString(row.approvalExpiresAt),
      items: waveItems.rows.map((item) => ({
        unitKey: item.unitKey,
        runOrder: item.runOrder,
        status: item.status,
        plannedRowCount: item.plannedRowCount,
        shipmentId: item.shipmentId,
        blockers: formatBatchQueueBlockers(item.blockers)
      }))
    };
  } catch (error) {
    if (isUndefinedTable(error)) {
      return null;
    }
    throw error;
  }
}

function toIsoString(value: string | Date | null | undefined): string | undefined {
  if (value instanceof Date) {
    return value.toISOString();
  }
  return typeof value === "string" ? value : undefined;
}
