/**
 * Staging-canary control-plane recorder (IP-16).
 *
 * Records a staging-canary *approval decision* (accepted or blocked) into the
 * platform audit log. This writes only to the platform control DB
 * (`ingestion_platform.ingestion_audit_log`) — never to a consumer target. The
 * promotion decision itself is computed by the pure
 * `staging-canary-policy.ts`; this module only persists the forensic record.
 *
 * It does not execute a shipment. The live staging write is a separate,
 * confirmation-gated runbook/CLI step.
 */

import { Client, type QueryResult } from "pg";

export interface StagingCanaryControlPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface RecordStagingCanaryApprovalInput {
  connectionString?: string;
  client?: StagingCanaryControlPgClientLike;
  projectKey: string;
  targetId: string;
  accepted: boolean;
  actor: { type: "operator" | "api"; id: string };
  /** Operator audit reason; required and recorded verbatim. */
  reason: string;
  /** Non-sensitive decision context (blocks, plan summary, principal). */
  payload: Record<string, unknown>;
  now?: string;
}

export interface RecordStagingCanaryApprovalResult {
  ok: boolean;
  auditId: string | null;
}

interface ProjectRow extends Record<string, unknown> {
  id: string;
}

export async function recordStagingCanaryApproval(
  input: RecordStagingCanaryApprovalInput
): Promise<RecordStagingCanaryApprovalResult> {
  if (!input.client && !input.connectionString) {
    throw new Error("Staging canary control recorder requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Staging canary control recorder client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  const now = input.now ?? new Date().toISOString();
  try {
    await client.query("begin");
    await client.query("set local statement_timeout = '5s'");

    const projectResult = await client.query<ProjectRow>(
      `
        select id::text as id
        from ingestion_platform.ingestion_projects
        where project_key = $1
      `,
      [input.projectKey]
    );
    const project = projectResult.rows[0];
    if (!project) {
      await client.query("rollback");
      throw new Error("Ingestion project was not found.");
    }

    const auditResult = await client.query<{ id: string }>(
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
        values ($1::bigint, $2, $3, $4, $5, $6, $7, $8::jsonb, $9::timestamptz)
        returning id::text as id
      `,
      [
        project.id,
        input.actor.type,
        input.actor.id,
        input.accepted ? "approve_staging_canary" : "reject_staging_canary",
        "target",
        input.targetId,
        input.reason,
        JSON.stringify({ ...input.payload, accepted: input.accepted }),
        now
      ]
    );

    await client.query("commit");
    return { ok: true, auditId: auditResult.rows[0]?.id ?? null };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}
