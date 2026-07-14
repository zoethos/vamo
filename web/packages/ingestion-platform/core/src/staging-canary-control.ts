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

export interface StagingCanaryShipmentItemForLedger {
  targetTable: string;
  operation: "insert" | "update" | "no_op";
  recordKey: string;
  idempotencyKey: string;
  keys: Record<string, unknown>;
  columns: string[];
  priorState: Record<string, unknown> | null;
}

export interface RecordStagingCanaryShipmentInput {
  connectionString?: string;
  client?: StagingCanaryControlPgClientLike;
  projectKey: string;
  targetId: string;
  targetAdapter: string;
  approvalAuditId: string;
  actor: { type: "operator" | "api"; id: string };
  reason: string;
  counts: { insert: number; update: number; noOp: number; writeCount: number };
  items: StagingCanaryShipmentItemForLedger[];
  /** Optional stable shipment key; defaults to staging-canary:{targetId}:approval:{approvalAuditId}. */
  shipmentKey?: string;
  /** Merged into shipment summary JSON (for example stagedContentHash evidence). */
  summaryExtras?: Record<string, unknown>;
  /**
   * Defaults to true. Set to false only when the caller already owns the
   * surrounding transaction on the provided client.
   */
  manageTransaction?: boolean;
  now?: string;
}

export interface RecordStagingCanaryShipmentResult {
  ok: boolean;
  shipmentId: string;
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

export async function recordStagingCanaryShipment(
  input: RecordStagingCanaryShipmentInput
): Promise<RecordStagingCanaryShipmentResult> {
  if (!input.client && !input.connectionString) {
    throw new Error("Staging canary shipment recorder requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Staging canary shipment recorder client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  const now = input.now ?? new Date().toISOString();
  const manageTransaction = input.manageTransaction ?? true;
  const shipmentKey =
    input.shipmentKey?.trim() ||
    `staging-canary:${input.targetId}:approval:${input.approvalAuditId}`;
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
    const project = projectResult.rows[0];
    if (!project) {
      if (manageTransaction) {
        await client.query("rollback");
      }
      throw new Error("Ingestion project was not found.");
    }

    const targetResult = await client.query<{ id: string }>(
      `
        insert into ingestion_platform.ingestion_targets (
          project_id,
          target_key,
          display_name,
          adapter,
          safety_mode,
          metadata,
          updated_at
        )
        values (
          $1::bigint,
          $2,
          $2,
          $3,
          'approved_write',
          $4::jsonb,
          $5::timestamptz
        )
        on conflict (project_id, target_key)
        do update set
          adapter = excluded.adapter,
          safety_mode = 'approved_write',
          metadata = ingestion_targets.metadata || excluded.metadata,
          updated_at = excluded.updated_at
        returning id::text as id
      `,
      [
        project.id,
        input.targetId,
        input.targetAdapter,
        JSON.stringify({ environment: "staging", lastApprovalAuditId: input.approvalAuditId }),
        now
      ]
    );
    const targetId = targetResult.rows[0]?.id;
    if (!targetId) {
      if (manageTransaction) {
        await client.query("rollback");
      }
      throw new Error("Ingestion target could not be recorded.");
    }

    const shipmentResult = await client.query<{ id: string }>(
      `
        insert into ingestion_platform.ingestion_shipments (
          project_id,
          target_id,
          shipment_key,
          mode,
          status,
          summary,
          started_at,
          finished_at,
          updated_at
        )
        values (
          $1::bigint,
          $2::bigint,
          $3,
          'approved_write',
          'succeeded',
          $4::jsonb,
          $5::timestamptz,
          $5::timestamptz,
          $5::timestamptz
        )
        on conflict (project_id, shipment_key)
        do update set
          status = excluded.status,
          summary = excluded.summary,
          finished_at = excluded.finished_at,
          updated_at = excluded.updated_at
        returning id::text as id
      `,
      [
        project.id,
        targetId,
        shipmentKey,
        JSON.stringify({
          environment: "staging",
          approvalAuditId: input.approvalAuditId,
          counts: input.counts,
          ...(input.summaryExtras ?? {})
        }),
        now
      ]
    );
    const shipmentId = shipmentResult.rows[0]?.id;
    if (!shipmentId) {
      if (manageTransaction) {
        await client.query("rollback");
      }
      throw new Error("Staging canary shipment could not be recorded.");
    }

    await client.query("delete from ingestion_platform.ingestion_shipment_items where shipment_id = $1::bigint", [
      shipmentId
    ]);

    for (const item of input.items) {
      await client.query(
        `
          insert into ingestion_platform.ingestion_shipment_items (
            shipment_id,
            target_table,
            operation,
            idempotency_key,
            record_key,
            payload,
            status,
            applied_at
          )
          values ($1::bigint, $2, $3, $4, $5, $6::jsonb, $7, $8::timestamptz)
        `,
        [
          shipmentId,
          item.targetTable,
          item.operation,
          item.idempotencyKey,
          item.recordKey,
          JSON.stringify({
            keys: item.keys,
            columns: item.columns,
            priorState: item.priorState
          }),
          item.operation === "no_op" ? "skipped" : "applied",
          item.operation === "no_op" ? null : now
        ]
      );
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
        values ($1::bigint, $2, $3, 'ship_staging_canary', 'shipment', $4, $5, $6::jsonb, $7::timestamptz)
        returning id::text as id
      `,
      [
        project.id,
        input.actor.type,
        input.actor.id,
        shipmentId,
        input.reason,
        JSON.stringify({
          accepted: true,
          approvalAuditId: input.approvalAuditId,
          targetId: input.targetId,
          counts: input.counts
        }),
        now
      ]
    );

    if (manageTransaction) {
      await client.query("commit");
    }
    return { ok: true, shipmentId, auditId: auditResult.rows[0]?.id ?? null };
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
