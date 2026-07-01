/**
 * Production-inbox control-plane recorder (IP-17).
 *
 * Records operator approval decisions and delivery ledger rows in the
 * Confluendo control DB. It never writes to a consumer target; live delivery is
 * handled by the confirmation-gated runbook/adapter.
 */

import { Client, type QueryResult } from "pg";

export interface ProductionInboxControlPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface RecordProductionInboxApprovalInput {
  connectionString?: string;
  client?: ProductionInboxControlPgClientLike;
  projectKey: string;
  targetId: string;
  accepted: boolean;
  actor: { type: "operator" | "api"; id: string };
  reason: string;
  payload: Record<string, unknown>;
  now?: string;
}

export interface RecordProductionInboxApprovalResult {
  ok: boolean;
  auditId: string | null;
}

export interface RecordProductionInboxDeliveryInput {
  connectionString?: string;
  client?: ProductionInboxControlPgClientLike;
  projectKey: string;
  targetId: string;
  targetAdapter: string;
  approvalAuditId: string;
  packageId: string;
  packageChecksum: string;
  itemCount: number;
  actor: { type: "operator" | "api"; id: string };
  reason: string;
  now?: string;
}

export interface RecordProductionInboxDeliveryResult {
  ok: boolean;
  shipmentId: string;
  auditId: string | null;
}

interface ProjectRow extends Record<string, unknown> {
  id: string;
}

export async function recordProductionInboxApproval(
  input: RecordProductionInboxApprovalInput
): Promise<RecordProductionInboxApprovalResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  const now = input.now ?? new Date().toISOString();
  try {
    await client.query("begin");
    await client.query("set local statement_timeout = '5s'");
    const project = await loadProject(client, input.projectKey);
    if (!project) {
      await client.query("rollback");
      throw new Error("Ingestion project was not found.");
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
        values ($1::bigint, $2, $3, $4, 'target', $5, $6, $7::jsonb, $8::timestamptz)
        returning id::text as id
      `,
      [
        project.id,
        input.actor.type,
        input.actor.id,
        input.accepted ? "approve_production_inbox" : "reject_production_inbox",
        input.targetId,
        input.reason,
        JSON.stringify({ ...input.payload, accepted: input.accepted }),
        now
      ]
    );
    await client.query("commit");
    return { ok: true, auditId: audit.rows[0]?.id ?? null };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    await closeClient(ownedClient);
  }
}

export async function recordProductionInboxDelivery(
  input: RecordProductionInboxDeliveryInput
): Promise<RecordProductionInboxDeliveryResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  const now = input.now ?? new Date().toISOString();
  const shipmentKey = `production-inbox:${input.targetId}:approval:${input.approvalAuditId}`;
  try {
    await client.query("begin");
    await client.query("set local statement_timeout = '5s'");
    const project = await loadProject(client, input.projectKey);
    if (!project) {
      await client.query("rollback");
      throw new Error("Ingestion project was not found.");
    }

    const target = await client.query<{ id: string }>(
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
        values ($1::bigint, $2, $2, $3, 'approved_write', $4::jsonb, $5::timestamptz)
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
        JSON.stringify({
          environment: "production",
          deliveryMode: "consumer_inbox",
          lastProductionInboxApprovalAuditId: input.approvalAuditId
        }),
        now
      ]
    );
    const targetId = target.rows[0]?.id;
    if (!targetId) {
      await client.query("rollback");
      throw new Error("Ingestion target could not be recorded.");
    }

    const shipment = await client.query<{ id: string }>(
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
          environment: "production",
          deliveryMode: "consumer_inbox",
          productionStatus: "production_inbox_delivered",
          approvalAuditId: input.approvalAuditId,
          packageId: input.packageId,
          packageChecksum: input.packageChecksum,
          itemCount: input.itemCount
        }),
        now
      ]
    );
    const shipmentId = shipment.rows[0]?.id;
    if (!shipmentId) {
      await client.query("rollback");
      throw new Error("Production inbox delivery could not be recorded.");
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
          'deliver_production_inbox',
          'shipment',
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
        shipmentId,
        input.reason,
        JSON.stringify({
          accepted: true,
          approvalAuditId: input.approvalAuditId,
          targetId: input.targetId,
          packageId: input.packageId,
          itemCount: input.itemCount
        }),
        now
      ]
    );

    await client.query("commit");
    return { ok: true, shipmentId, auditId: audit.rows[0]?.id ?? null };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    await closeClient(ownedClient);
  }
}

async function openClient(
  client?: ProductionInboxControlPgClientLike,
  connectionString?: string
): Promise<{ client: ProductionInboxControlPgClientLike; ownedClient?: Client }> {
  if (!client && !connectionString) {
    throw new Error("Production inbox control recorder requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Production inbox control recorder client could not be initialized.");
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
  client: ProductionInboxControlPgClientLike,
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
