/**
 * Batch queue control-plane mutations (IP-18.3).
 *
 * Writes only to Confluendo control-plane queue rows and audit log. It never
 * calls providers and never writes to Vamo staging or production targets.
 */

import { Client, type QueryResult } from "pg";

import type { BatchControlActor } from "./batch-control-actor.js";

export interface BatchQueueMutationPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface ScheduleBatchDryRunInput {
  connectionString?: string;
  client?: BatchQueueMutationPgClientLike;
  projectKey: string;
  planId: string;
  targetKey: string;
  actor: BatchControlActor;
  reason: string;
  payload: Record<string, unknown>;
  /** When set, only these queue unit keys may transition to dry_run_ready. */
  unitKeys?: string[];
  now?: string;
}

export interface ScheduleBatchDryRunResult {
  ok: true;
  batchPlanId: string;
  auditId: string | null;
  scheduledCount: number;
  alreadyScheduledCount: number;
  unitKeys: string[];
}

interface ProjectRow extends Record<string, unknown> {
  id: string;
}

interface PlanRow extends Record<string, unknown> {
  id: string;
}

interface UpdatedItemRow extends Record<string, unknown> {
  unitKey: string;
}

interface CountRow extends Record<string, unknown> {
  count: string;
}

export async function scheduleBatchDryRun(
  input: ScheduleBatchDryRunInput
): Promise<ScheduleBatchDryRunResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  const now = input.now ?? new Date().toISOString();

  try {
    await client.query("begin");
    await client.query("set local statement_timeout = '5s'");

    const project = await loadProject(client, input.projectKey);
    if (!project) {
      throw new Error(`Unknown ingestion project "${input.projectKey}".`);
    }

    const plan = await loadActivePlan(client, project.id, input.planId, input.targetKey);
    if (!plan) {
      throw new Error(`Active batch plan "${input.planId}" was not found.`);
    }

    const unitFilter =
      input.unitKeys && input.unitKeys.length > 0
        ? "and unit_key = any($3::text[])"
        : "";
    const updateValues: unknown[] = [plan.id, now];
    if (input.unitKeys && input.unitKeys.length > 0) {
      updateValues.push(input.unitKeys);
    }

    const updated = await client.query<UpdatedItemRow>(
      `
        update ingestion_platform.ingestion_batch_queue_items
        set status = 'dry_run_ready',
            updated_at = $2::timestamptz
        where batch_plan_id = $1::bigint
          and status = 'ready_for_dry_run'
          ${unitFilter}
        returning unit_key as "unitKey"
      `,
      updateValues
    );

    const alreadyScheduled = await client.query<CountRow>(
      `
        select count(*)::text as count
        from ingestion_platform.ingestion_batch_queue_items
        where batch_plan_id = $1::bigint
          and status = 'dry_run_ready'
      `,
      [plan.id]
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
        values ($1::bigint, $2, $3, 'schedule_batch_dry_run', 'batch_plan', $4, $5, $6::jsonb, $7::timestamptz)
        returning id::text as id
      `,
      [
        project.id,
        input.actor.type,
        input.actor.id,
        plan.id,
        input.reason,
        JSON.stringify({
          ...input.payload,
          accepted: true,
          projectKey: input.projectKey,
          planId: input.planId,
          targetKey: input.targetKey,
          scheduledCount: updated.rows.length,
          alreadyScheduledCount: Number.parseInt(alreadyScheduled.rows[0]?.count ?? "0", 10),
          unitKeys: updated.rows.map((row) => row.unitKey)
        }),
        now
      ]
    );

    await client.query("commit");

    return {
      ok: true,
      batchPlanId: plan.id,
      auditId: audit.rows[0]?.id ?? null,
      scheduledCount: updated.rows.length,
      alreadyScheduledCount: Number.parseInt(alreadyScheduled.rows[0]?.count ?? "0", 10),
      unitKeys: updated.rows.map((row) => row.unitKey)
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    await closeClient(ownedClient);
  }
}

async function openClient(
  client?: BatchQueueMutationPgClientLike,
  connectionString?: string
): Promise<{ client: BatchQueueMutationPgClientLike; ownedClient?: Client }> {
  if (!client && !connectionString) {
    throw new Error("Batch queue mutation requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Batch queue mutation client could not be initialized.");
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
  client: BatchQueueMutationPgClientLike,
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
  client: BatchQueueMutationPgClientLike,
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
