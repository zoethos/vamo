/**
 * Batch queue control-plane persistence (IP-18.2).
 *
 * Writes only to Confluendo control tables (`ingestion_batch_plans`,
 * `ingestion_batch_queue_items`). No provider calls, no consumer target writes.
 */

import { Client, type QueryResult } from "pg";

import {
  mapSnapshotToPersistenceBundle,
  type BatchQueuePersistenceBundle
} from "./batch-queue-persistence.js";
import type { BatchPlanSpec } from "./batch-plan-spec.js";
import type { BatchQueueSnapshot } from "./batch-queue-read-model.js";

export interface BatchQueueControlPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface PersistBatchQueueSnapshotInput {
  connectionString?: string;
  client?: BatchQueueControlPgClientLike;
  projectKey: string;
  snapshot: BatchQueueSnapshot;
  spec: BatchPlanSpec | Record<string, unknown>;
  planStatus?: "active" | "archived";
  now?: string;
  manageTransaction?: boolean;
}

export interface PersistBatchQueueSnapshotResult {
  ok: true;
  batchPlanId: string;
}

interface ProjectRow extends Record<string, unknown> {
  id: string;
}

interface PlanIdRow extends Record<string, unknown> {
  id: string;
}

export async function persistBatchQueueSnapshot(
  input: PersistBatchQueueSnapshotInput
): Promise<PersistBatchQueueSnapshotResult> {
  if (!input.client && !input.connectionString) {
    throw new Error("Batch queue persistence requires a server-side connection string or client.");
  }

  const bundle = mapSnapshotToPersistenceBundle(input.snapshot, input.spec, {
    planStatus: input.planStatus
  });
  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Batch queue persistence client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  const now = input.now ?? new Date().toISOString();
  const manageTransaction = input.manageTransaction ?? true;
  try {
    if (manageTransaction) {
      await client.query("begin");
      await client.query("set local statement_timeout = '5s'");
    }

    const projectResult = await client.query<ProjectRow>(
      `
        select id::text as id
        from ingestion_platform.ingestion_projects
        where project_key = $1
      `,
      [input.projectKey]
    );
    const projectId = projectResult.rows[0]?.id;
    if (!projectId) {
      throw new Error(`Unknown ingestion project "${input.projectKey}".`);
    }

    const planResult = await client.query<PlanIdRow>(
      `
        insert into ingestion_platform.ingestion_batch_plans (
          project_id,
          plan_key,
          source_key,
          target_key,
          target_environment,
          safety_mode,
          spec,
          plan_summary,
          status,
          updated_at
        )
        values ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9, $10::timestamptz)
        on conflict (project_id, plan_key) do update
          set source_key = excluded.source_key,
              target_key = excluded.target_key,
              target_environment = excluded.target_environment,
              safety_mode = excluded.safety_mode,
              spec = excluded.spec,
              plan_summary = excluded.plan_summary,
              status = excluded.status,
              updated_at = excluded.updated_at
        returning id::text as id
      `,
      [
        projectId,
        bundle.plan.planKey,
        bundle.plan.sourceKey,
        bundle.plan.targetKey,
        bundle.plan.targetEnvironment,
        bundle.plan.safetyMode,
        JSON.stringify(bundle.plan.spec),
        JSON.stringify(bundle.plan.planSummary),
        bundle.plan.status,
        now
      ]
    );
    const batchPlanId = planResult.rows[0]?.id;
    if (!batchPlanId) {
      throw new Error("Batch plan upsert did not return an id.");
    }

    for (const item of bundle.items) {
      await client.query(
        `
          insert into ingestion_platform.ingestion_batch_queue_items (
            batch_plan_id,
            unit_key,
            country_code,
            geography_key,
            geography_label,
            geography_kind,
            category,
            source_key,
            target_key,
            target_environment,
            status,
            priority,
            run_order,
            blockers,
            proposal,
            run_report,
            updated_at
          )
          values (
            $1,
            $2,
            $3,
            $4,
            $5,
            $6,
            $7,
            $8,
            $9,
            $10,
            $11,
            $12,
            $13,
            $14::jsonb,
            $15::jsonb,
            $16::jsonb,
            $17::timestamptz
          )
          on conflict (batch_plan_id, unit_key) do update
            set country_code = excluded.country_code,
                geography_key = excluded.geography_key,
                geography_label = excluded.geography_label,
                geography_kind = excluded.geography_kind,
                category = excluded.category,
                source_key = excluded.source_key,
                target_key = excluded.target_key,
                target_environment = excluded.target_environment,
                status = excluded.status,
                priority = excluded.priority,
                run_order = excluded.run_order,
                blockers = excluded.blockers,
                proposal = excluded.proposal,
                run_report = excluded.run_report,
                updated_at = excluded.updated_at
        `,
        [
          batchPlanId,
          item.unitKey,
          item.countryCode,
          item.geographyKey,
          item.geographyLabel,
          item.geographyKind,
          item.category,
          item.sourceKey,
          item.targetKey,
          item.targetEnvironment,
          item.status,
          item.priority,
          item.runOrder,
          JSON.stringify(item.blockers),
          item.proposal ? JSON.stringify(item.proposal) : null,
          item.runReport ? JSON.stringify(item.runReport) : null,
          now
        ]
      );
    }

    await client.query("commit");
    return { ok: true, batchPlanId };
  } catch (error) {
    if (manageTransaction) {
      await client.query("rollback");
    }
    throw error;
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

export function buildSamplePersistenceBundle(
  snapshot: BatchQueueSnapshot,
  spec: BatchPlanSpec | Record<string, unknown>
): BatchQueuePersistenceBundle {
  return mapSnapshotToPersistenceBundle(snapshot, spec);
}
