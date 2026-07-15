/**
 * Control-plane adapter for snapshot activation requests (IP-18.8.14).
 *
 * The app role may create and read requests through reviewed SQL functions.
 * Claim and completion remain worker/owner-only operations.
 */
import { Client, type QueryResult } from "pg";

import { createBoundedPostgresReadClientConfig } from "./postgres-read-timeouts.js";
import {
  isSnapshotActivationRequestStatus,
  SNAPSHOT_ACTIVATION_REQUEST_ACTIVE_STATUSES,
  SNAPSHOT_ACTIVATION_REQUEST_DEFAULT_LEASE_SECONDS,
  type SnapshotActivationRequestRecord,
  type SnapshotActivationRequestStatus
} from "./snapshot-activation-request.js";

export interface SnapshotActivationRequestPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface CreateSnapshotActivationRequestInput {
  connectionString?: string;
  client?: SnapshotActivationRequestPgClientLike;
  projectKey: string;
  planKey: string;
  commissionRequestId: string;
  releaseId: string;
  actor: { type: string; id: string };
  auditReason: string;
}

export interface CreateSnapshotActivationRequestResult {
  ok: true;
  requestId: string;
  auditId: string;
  status: "requested";
  releaseId: string;
}

export type ClaimSnapshotActivationRequestResult =
  | { ok: true; idempotentReplay: boolean; leaseReclaimed?: boolean; request: SnapshotActivationRequestRecord }
  | { ok: false; code: "no_pending_request" };

export async function createSnapshotActivationRequest(
  input: CreateSnapshotActivationRequestInput
): Promise<CreateSnapshotActivationRequestResult> {
  return withClient(input, "write", async (client) => {
    const response = await client.query<{ result: Record<string, unknown> }>(
      `
        select ingestion_platform.create_snapshot_activation_request(
          $1, $2, $3::bigint, $4, $5, $6, $7
        ) as result
      `,
      [
        input.projectKey,
        input.planKey,
        input.commissionRequestId,
        input.releaseId,
        input.actor.type,
        input.actor.id,
        input.auditReason
      ]
    );
    const result = response.rows[0]?.result ?? {};
    return {
      ok: true,
      requestId: String(result.requestId),
      auditId: String(result.auditId),
      status: "requested",
      releaseId: String(result.releaseId)
    };
  });
}

export async function claimSnapshotActivationRequest(input: {
  connectionString?: string;
  client?: SnapshotActivationRequestPgClientLike;
  workerId: string;
  workerRunKey: string;
  leaseSeconds?: number;
}): Promise<ClaimSnapshotActivationRequestResult> {
  return withClient(input, "write", async (client) => {
    const leaseSeconds = Math.max(1, input.leaseSeconds ?? SNAPSHOT_ACTIVATION_REQUEST_DEFAULT_LEASE_SECONDS);
    const response = await client.query<{ result: Record<string, unknown> }>(
      `select ingestion_platform.claim_snapshot_activation_request($1, $2, $3) as result`,
      [input.workerId, input.workerRunKey, leaseSeconds]
    );
    const result = response.rows[0]?.result ?? {};
    if (result.ok !== true) {
      return { ok: false, code: "no_pending_request" };
    }
    return {
      ok: true,
      idempotentReplay: result.idempotentReplay === true,
      leaseReclaimed: result.leaseReclaimed === true,
      request: mapClaimResult(result)
    };
  });
}

export async function completeSnapshotActivationRequest(input: {
  connectionString?: string;
  client?: SnapshotActivationRequestPgClientLike;
  requestId: string;
  workerRunKey: string;
  status: Extract<SnapshotActivationRequestStatus, "activated" | "failed">;
  bindingId?: string;
  activationAuditId?: string;
  errorCode?: string;
  errorMessage?: string;
}): Promise<{ ok: true; idempotentReplay: boolean; requestId: string; status: SnapshotActivationRequestStatus; auditId?: string }> {
  return withClient(input, "write", async (client) => {
    const response = await client.query<{ result: Record<string, unknown> }>(
      `
        select ingestion_platform.complete_snapshot_activation_request(
          $1::bigint, $2, $3, $4, $5, $6, $7
        ) as result
      `,
      [
        input.requestId,
        input.workerRunKey,
        input.status,
        input.bindingId ?? null,
        input.activationAuditId ?? null,
        input.errorCode ?? null,
        input.errorMessage ?? null
      ]
    );
    const result = response.rows[0]?.result ?? {};
    return {
      ok: true,
      idempotentReplay: result.idempotentReplay === true,
      requestId: String(result.requestId),
      status: String(result.status) as SnapshotActivationRequestStatus,
      auditId: typeof result.auditId === "string" ? result.auditId : undefined
    };
  });
}

export async function loadLatestSnapshotActivationRequest(input: {
  connectionString?: string;
  client?: SnapshotActivationRequestPgClientLike;
  projectKey: string;
  planKey: string;
}): Promise<SnapshotActivationRequestRecord | null> {
  return withClient(input, "read", async (client) => {
    const response = await client.query<ActivationRow>(
      `
        select
          r.id::text as request_id,
          p.project_key,
          bp.plan_key,
          r.commission_request_id::text as commission_request_id,
          r.release_id,
          r.status,
          r.audit_reason,
          r.requested_by_type,
          r.requested_by_id,
          r.requested_at,
          r.claimed_at,
          r.claimed_by_id,
          r.worker_run_key,
          r.claim_expires_at,
          r.attempt_count,
          r.binding_id::text as binding_id,
          r.activation_audit_id::text as activation_audit_id,
          r.error_code,
          r.error_message,
          r.completed_at
        from ingestion_platform.ingestion_snapshot_activation_requests r
        join ingestion_platform.ingestion_projects p on p.id = r.project_id
        join ingestion_platform.ingestion_batch_plans bp on bp.id = r.batch_plan_id
        where p.project_key = $1 and bp.plan_key = $2
        order by r.requested_at desc, r.id desc
        limit 1
      `,
      [input.projectKey, input.planKey]
    );
    return response.rows[0] ? mapActivationRow(response.rows[0]) : null;
  });
}

export async function hasActiveSnapshotActivationRequest(input: {
  connectionString?: string;
  client?: SnapshotActivationRequestPgClientLike;
  projectKey: string;
  planKey: string;
}): Promise<boolean> {
  return withClient(input, "read", async (client) => {
    const response = await client.query<{ exists: boolean }>(
      `
        select exists (
          select 1
          from ingestion_platform.ingestion_snapshot_activation_requests r
          join ingestion_platform.ingestion_projects p on p.id = r.project_id
          join ingestion_platform.ingestion_batch_plans bp on bp.id = r.batch_plan_id
          where p.project_key = $1
            and bp.plan_key = $2
            and r.status = any($3::text[])
        ) as exists
      `,
      [input.projectKey, input.planKey, SNAPSHOT_ACTIVATION_REQUEST_ACTIVE_STATUSES]
    );
    return response.rows[0]?.exists === true;
  });
}

interface ActivationRow extends Record<string, unknown> {
  request_id: string;
  project_key: string;
  plan_key: string;
  commission_request_id: string;
  release_id: string;
  status: string;
  audit_reason: string;
  requested_by_type: string;
  requested_by_id: string;
  requested_at: string | Date;
  claimed_at?: string | Date | null;
  claimed_by_id?: string | null;
  worker_run_key?: string | null;
  claim_expires_at?: string | Date | null;
  attempt_count?: number | null;
  binding_id?: string | null;
  activation_audit_id?: string | null;
  error_code?: string | null;
  error_message?: string | null;
  completed_at?: string | Date | null;
}

function mapActivationRow(row: ActivationRow): SnapshotActivationRequestRecord {
  if (!isSnapshotActivationRequestStatus(row.status)) {
    throw new Error(`Unknown snapshot activation request status "${row.status}".`);
  }
  return {
    requestId: row.request_id,
    projectKey: row.project_key,
    planKey: row.plan_key,
    commissionRequestId: row.commission_request_id,
    releaseId: row.release_id,
    status: row.status,
    auditReason: row.audit_reason,
    requestedByType: row.requested_by_type,
    requestedById: row.requested_by_id,
    requestedAt: toIsoString(row.requested_at),
    claimedAt: row.claimed_at ? toIsoString(row.claimed_at) : undefined,
    claimedById: row.claimed_by_id ?? undefined,
    workerRunKey: row.worker_run_key ?? undefined,
    claimExpiresAt: row.claim_expires_at ? toIsoString(row.claim_expires_at) : undefined,
    attemptCount: row.attempt_count ?? undefined,
    bindingId: row.binding_id ?? undefined,
    activationAuditId: row.activation_audit_id ?? undefined,
    errorCode: row.error_code ?? undefined,
    errorMessage: row.error_message ?? undefined,
    completedAt: row.completed_at ? toIsoString(row.completed_at) : undefined
  };
}

function mapClaimResult(result: Record<string, unknown>): SnapshotActivationRequestRecord {
  const request = mapActivationRow({
    request_id: String(result.requestId),
    project_key: String(result.projectKey),
    plan_key: String(result.planKey),
    commission_request_id: String(result.commissionRequestId),
    release_id: String(result.releaseId),
    status: String(result.status),
    audit_reason: "",
    requested_by_type: "operator",
    requested_by_id: "",
    requested_at: new Date(0),
    claim_expires_at:
      typeof result.claimExpiresAt === "string" || result.claimExpiresAt instanceof Date
        ? result.claimExpiresAt
        : undefined,
    attempt_count: typeof result.attemptCount === "number" ? result.attemptCount : undefined
  });
  return {
    ...request,
    bindingId: typeof result.bindingId === "string" ? result.bindingId : undefined,
    activationAuditId: typeof result.activationAuditId === "string" ? result.activationAuditId : undefined,
    errorCode: typeof result.errorCode === "string" ? result.errorCode : undefined,
    errorMessage: typeof result.errorMessage === "string" ? result.errorMessage : undefined
  };
}

async function withClient<T>(
  input: { connectionString?: string; client?: SnapshotActivationRequestPgClientLike },
  mode: "read" | "write",
  run: (client: SnapshotActivationRequestPgClientLike) => Promise<T>
): Promise<T> {
  if (input.client) {
    return run(input.client);
  }
  if (!input.connectionString) {
    throw new Error("Control database connection is required for snapshot activation requests.");
  }
  const client = new Client(
    mode === "read"
      ? createBoundedPostgresReadClientConfig(input.connectionString)
      : { connectionString: input.connectionString }
  );
  try {
    await client.connect();
    return await run(client);
  } finally {
    await client.end();
  }
}

function toIsoString(value: string | Date): string {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}
