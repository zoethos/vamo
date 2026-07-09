/**
 * Control-plane ramp promotion adapter (IP-18.7.4).
 *
 * The database function owns the atomic mutation, audit row, and event row.
 * This module is intentionally thin so route code cannot bypass SQL transition
 * checks with a direct table update.
 */

import { Client, type QueryResult } from "pg";

import type { CommandActorType } from "./commands.js";
import type { AutonomyRampMode } from "./autonomy-ramp-policy.js";

export interface AutonomyRampControlPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface PromoteAutonomyRampInput {
  connectionString?: string;
  client?: AutonomyRampControlPgClientLike;
  projectKey: string;
  policyKey: string;
  expectedCurrentMode: AutonomyRampMode;
  requestedMode: AutonomyRampMode;
  actor: {
    type: CommandActorType;
    id: string;
  };
  auditReason: string;
}

export interface PromoteAutonomyRampResult {
  ok: true;
  policyId: string;
  fromMode: AutonomyRampMode;
  toMode: AutonomyRampMode;
  auditId: string;
}

export interface AutonomyRampReadiness {
  policyId: string;
  policyKey: string;
  currentMode: AutonomyRampMode;
  since: string;
  runs: {
    advanced: number;
    completed: number;
    failed: number;
    paused: number;
  };
  stagingCanarySucceededUnits: number;
}

interface PromoteRow extends Record<string, unknown> {
  result: {
    ok?: unknown;
    policyId?: unknown;
    fromMode?: unknown;
    toMode?: unknown;
    auditId?: unknown;
  };
}

interface ReadinessPolicyRow extends Record<string, unknown> {
  policyId: string;
  policyKey: string;
  currentMode: AutonomyRampMode;
  since: string | Date;
}

interface RunCountsRow extends Record<string, unknown> {
  advanced: string;
  completed: string;
  failed: string;
  paused: string;
}

interface UnitCountRow extends Record<string, unknown> {
  count: string;
}

export async function promoteAutonomyRamp(
  input: PromoteAutonomyRampInput
): Promise<PromoteAutonomyRampResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);

  try {
    const result = await client.query<PromoteRow>(
      `
        select ingestion_platform.promote_autonomy_ramp(
          $1,
          $2,
          $3,
          $4,
          $5,
          $6,
          $7
        ) as result
      `,
      [
        input.projectKey,
        input.policyKey,
        input.expectedCurrentMode,
        input.requestedMode,
        input.actor.type,
        input.actor.id,
        input.auditReason
      ]
    );

    const row = result.rows[0]?.result;
    if (
      row?.ok !== true ||
      typeof row.policyId !== "string" ||
      typeof row.fromMode !== "string" ||
      typeof row.toMode !== "string" ||
      typeof row.auditId !== "string"
    ) {
      throw new Error("Autonomy ramp promotion returned an invalid control response.");
    }

    return {
      ok: true,
      policyId: row.policyId,
      fromMode: row.fromMode as AutonomyRampMode,
      toMode: row.toMode as AutonomyRampMode,
      auditId: row.auditId
    };
  } catch (error) {
    throw normalizeRampControlError(error);
  } finally {
    await closeClient(ownedClient);
  }
}

export async function loadAutonomyRampReadiness(input: {
  connectionString?: string;
  client?: AutonomyRampControlPgClientLike;
  projectKey: string;
  policyKey: string;
}): Promise<AutonomyRampReadiness | null> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);

  try {
    const policy = await client.query<ReadinessPolicyRow>(
      `
        with policy as (
          select
            p.id as project_id,
            ap.id as policy_id,
            ap.policy_key,
            ap.ramp_mode,
            coalesce(
              (
                select max(e.created_at)
                from ingestion_platform.ingestion_events e
                where e.project_id = p.id
                  and e.signal = 'autonomy_ramp'
              ),
              now() - interval '7 days'
            ) as since
          from ingestion_platform.ingestion_autonomy_policies ap
          join ingestion_platform.ingestion_projects p on p.id = ap.project_id
          where p.project_key = $1
            and ap.policy_key = $2
        )
        select
          policy_id::text as "policyId",
          policy_key as "policyKey",
          ramp_mode as "currentMode",
          since
        from policy
      `,
      [input.projectKey, input.policyKey]
    );

    const row = policy.rows[0];
    if (!row) {
      return null;
    }

    const counts = await client.query<RunCountsRow>(
      `
        select
          count(*) filter (where status = 'advanced')::text as advanced,
          count(*) filter (where status = 'completed')::text as completed,
          count(*) filter (where status = 'failed')::text as failed,
          count(*) filter (where status = 'paused')::text as paused
        from ingestion_platform.ingestion_autonomy_runs
        where policy_id = $1::bigint
          and created_at >= $2::timestamptz
      `,
      [row.policyId, row.since]
    );

    const staging = await client.query<UnitCountRow>(
      `
        select count(*)::text as count
        from ingestion_platform.ingestion_batch_queue_items qi
        join ingestion_platform.ingestion_batch_plans bp on bp.id = qi.batch_plan_id
        join ingestion_platform.ingestion_projects p on p.id = bp.project_id
        where p.project_key = $1
          and bp.target_key = (
            select target_key
            from ingestion_platform.ingestion_autonomy_policies
            where id = $2::bigint
          )
          and qi.status = 'staging_canary_succeeded'
      `,
      [input.projectKey, row.policyId]
    );

    const runCounts = counts.rows[0];
    return {
      policyId: row.policyId,
      policyKey: row.policyKey,
      currentMode: row.currentMode,
      since: row.since instanceof Date ? row.since.toISOString() : row.since,
      runs: {
        advanced: Number(runCounts?.advanced ?? 0),
        completed: Number(runCounts?.completed ?? 0),
        failed: Number(runCounts?.failed ?? 0),
        paused: Number(runCounts?.paused ?? 0)
      },
      stagingCanarySucceededUnits: Number(staging.rows[0]?.count ?? 0)
    };
  } finally {
    await closeClient(ownedClient);
  }
}

async function openClient(
  client?: AutonomyRampControlPgClientLike,
  connectionString?: string
): Promise<{ client: AutonomyRampControlPgClientLike; ownedClient?: Client }> {
  if (!client && !connectionString) {
    throw new Error("Autonomy ramp control requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Autonomy ramp control client could not be initialized.");
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

function normalizeRampControlError(error: unknown): Error {
  if (error instanceof Error) {
    return error;
  }
  return new Error(String(error));
}
