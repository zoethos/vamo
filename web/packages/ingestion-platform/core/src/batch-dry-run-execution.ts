/**
 * Batch dry-run execution control-plane writer (IP-18.4).
 *
 * Executes bounded fixture-only dry runs against persisted queue items and
 * records control-plane state only. Never calls live providers or writes to
 * Vamo staging/production targets.
 */

import { Client, type QueryResult } from "pg";

import type { BatchDryRunExecutionPlan } from "./batch-dry-run-execution-policy.js";
import {
  simulateBatchDryRunUnit,
  type BatchDryRunUnitReport
} from "./batch-dry-run-simulator.js";
import type { BatchQueueItem } from "./batch-queue-read-model.js";

export interface BatchDryRunExecutionPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface ExecuteBatchDryRunInput {
  connectionString?: string;
  client?: BatchDryRunExecutionPgClientLike;
  projectKey: string;
  plan: BatchDryRunExecutionPlan;
  deps?: {
    buildUnitReport?: (input: {
      unit: BatchQueueItem;
      executionKey: string;
      now: string;
    }) => Promise<BatchDryRunUnitReport> | BatchDryRunUnitReport;
  };
  now?: string;
}

export interface ExecuteBatchDryRunResult {
  ok: true;
  executionId: string;
  executionKey: string;
  auditId: string | null;
  idempotentReplay: boolean;
  succeededCount: number;
  blockedCount: number;
  unitKeys: string[];
  safetySummary: string[];
}

interface ProjectRow extends Record<string, unknown> {
  id: string;
}

interface PlanRow extends Record<string, unknown> {
  id: string;
}

interface ExecutionRow extends Record<string, unknown> {
  id: string;
  status: string;
  summary: Record<string, unknown> | null;
}

export async function executeBatchDryRun(
  input: ExecuteBatchDryRunInput
): Promise<ExecuteBatchDryRunResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  const now = input.now ?? new Date().toISOString();
  const plan = input.plan;

  try {
    await client.query("begin");
    await client.query("set local statement_timeout = '10s'");

    const project = await loadProject(client, input.projectKey);
    if (!project) {
      throw new Error(`Unknown ingestion project "${input.projectKey}".`);
    }

    const batchPlan = await loadActivePlan(client, project.id, plan.planId, plan.targetKey);
    if (!batchPlan) {
      throw new Error(`Active batch plan "${plan.planId}" was not found.`);
    }

    const existing = await client.query<ExecutionRow>(
      `
        select id::text as id, status, summary
        from ingestion_platform.ingestion_batch_dry_run_executions
        where batch_plan_id = $1::bigint
          and execution_key = $2
      `,
      [batchPlan.id, plan.executionKey]
    );

    if (existing.rows[0]?.status === "succeeded" || existing.rows[0]?.status === "partial") {
      const summary = existing.rows[0].summary ?? {};
      await client.query("commit");
      return {
        ok: true,
        executionId: existing.rows[0].id,
        executionKey: plan.executionKey,
        auditId: typeof summary.auditId === "string" ? summary.auditId : plan.auditId ?? null,
        idempotentReplay: true,
        succeededCount: Number(summary.succeededCount ?? 0),
        blockedCount: Number(summary.blockedCount ?? 0),
        unitKeys: Array.isArray(summary.unitKeys) ? summary.unitKeys.map(String) : plan.unitKeys,
        safetySummary: plan.safetySummary
      };
    }

    let executionId = existing.rows[0]?.id;
    if (!executionId) {
      const inserted = await client.query<{ id: string }>(
        `
          insert into ingestion_platform.ingestion_batch_dry_run_executions (
            batch_plan_id,
            execution_key,
            target_key,
            target_environment,
            max_units,
            audit_id,
            audit_reason,
            actor_type,
            actor_id,
            status,
            summary,
            created_at,
            updated_at
          )
          values ($1::bigint, $2, $3, $4, $5, $6, $7, $8, $9, 'running', '{}'::jsonb, $10::timestamptz, $10::timestamptz)
          returning id::text as id
        `,
        [
          batchPlan.id,
          plan.executionKey,
          plan.targetKey,
          plan.targetEnvironment,
          plan.maxUnits,
          plan.auditId ?? null,
          plan.auditReason,
          plan.actor.type,
          plan.actor.id,
          now
        ]
      );
      executionId = inserted.rows[0]?.id;
    } else {
      await client.query(
        `
          update ingestion_platform.ingestion_batch_dry_run_executions
          set status = 'running',
              updated_at = $2::timestamptz
          where id = $1::bigint
        `,
        [executionId, now]
      );
    }

    if (!executionId) {
      throw new Error("Batch dry-run execution row could not be created.");
    }

    let succeededCount = 0;
    let blockedCount = 0;
    const processedUnitKeys: string[] = [];

    for (const unit of plan.selectedUnits) {
      processedUnitKeys.push(unit.unitKey);
      await client.query(
        `
          update ingestion_platform.ingestion_batch_queue_items
          set status = 'dry_run_running',
              updated_at = $3::timestamptz
          where batch_plan_id = $1::bigint
            and unit_key = $2
            and status = 'dry_run_ready'
        `,
        [batchPlan.id, unit.unitKey, now]
      );

      const report = input.deps?.buildUnitReport
        ? await input.deps.buildUnitReport({
            unit,
            executionKey: plan.executionKey,
            now
          })
        : simulateBatchDryRunUnit({
            executionKey: plan.executionKey,
            unitKey: unit.unitKey,
            geography: unit.geography,
            category: unit.category,
            targetKey: unit.targetKey,
            targetEnvironment: unit.targetEnvironment,
            now
          });

      await client.query(
        `
          update ingestion_platform.ingestion_batch_queue_items
          set status = 'dry_run_succeeded',
              run_report = $3::jsonb,
              blockers = '[]'::jsonb,
              updated_at = $4::timestamptz
          where batch_plan_id = $1::bigint
            and unit_key = $2
        `,
        [batchPlan.id, unit.unitKey, JSON.stringify(report), now]
      );
      succeededCount += 1;
    }

    const summary = {
      executionKey: plan.executionKey,
      auditId: plan.auditId ?? null,
      succeededCount,
      blockedCount,
      runningCount: 0,
      unitKeys: processedUnitKeys,
      safetySummary: plan.safetySummary
    };

    const finalStatus = blockedCount > 0 && succeededCount > 0 ? "partial" : "succeeded";

    await client.query(
      `
        update ingestion_platform.ingestion_batch_dry_run_executions
        set status = $2,
            summary = $3::jsonb,
            finished_at = $4::timestamptz,
            updated_at = $4::timestamptz
        where id = $1::bigint
      `,
      [executionId, finalStatus, JSON.stringify(summary), now]
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
        values ($1::bigint, $2, $3, 'execute_batch_dry_run', 'batch_dry_run_execution', $4, $5, $6::jsonb, $7::timestamptz)
        returning id::text as id
      `,
      [
        project.id,
        plan.actor.type,
        plan.actor.id,
        executionId,
        plan.auditReason,
        JSON.stringify({
          accepted: true,
          executionKey: plan.executionKey,
          projectKey: input.projectKey,
          planId: plan.planId,
          targetKey: plan.targetKey,
          targetEnvironment: plan.targetEnvironment,
          succeededCount,
          blockedCount,
          unitKeys: processedUnitKeys,
          auditId: plan.auditId ?? null,
          safetySummary: plan.safetySummary
        }),
        now
      ]
    );

    await client.query("commit");

    return {
      ok: true,
      executionId,
      executionKey: plan.executionKey,
      auditId: audit.rows[0]?.id ?? null,
      idempotentReplay: false,
      succeededCount,
      blockedCount,
      unitKeys: processedUnitKeys,
      safetySummary: plan.safetySummary
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    await closeClient(ownedClient);
  }
}

async function openClient(
  client?: BatchDryRunExecutionPgClientLike,
  connectionString?: string
): Promise<{ client: BatchDryRunExecutionPgClientLike; ownedClient?: Client }> {
  if (!client && !connectionString) {
    throw new Error("Batch dry-run execution requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Batch dry-run execution client could not be initialized.");
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
  client: BatchDryRunExecutionPgClientLike,
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
  client: BatchDryRunExecutionPgClientLike,
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
