import { Client, type QueryResult } from "pg";

import {
  mapPersistenceBundleToSnapshot,
  type PersistedBatchPlanRow,
  type PersistedBatchQueueItemRow
} from "./batch-queue-persistence.js";
import type { BatchQueueItemStatus, BatchQueueSnapshot } from "./batch-queue-read-model.js";

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
        blockers: Array.isArray(row.blockers) ? row.blockers.map(String) : [],
        proposal: row.proposal,
        runReport: row.runReport
      }))
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
