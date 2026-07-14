/**
 * Control-plane snapshot commission request adapter (IP-18.8.13).
 */

import { Client, type QueryResult } from "pg";

import {
  isSnapshotCommissionRequestStatus,
  SNAPSHOT_COMMISSION_ACTIVE_STATUSES,
  type SnapshotCommissionRequestRecord,
  type SnapshotCommissionRequestStatus
} from "./snapshot-commission-request.js";

export interface SnapshotCommissionPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface CreateSnapshotCommissionRequestInput {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  projectKey: string;
  planKey: string;
  sourceKey: string;
  countries: readonly string[];
  categories: readonly string[];
  maxRowsPerScope: number;
  actor: { type: string; id: string };
  auditReason: string;
}

export interface CreateSnapshotCommissionRequestResult {
  ok: true;
  requestId: string;
  auditId: string;
  status: "requested";
}

export interface ClaimSnapshotCommissionRequestInput {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  workerId: string;
  workerRunKey: string;
}

export type ClaimSnapshotCommissionRequestResult =
  | {
      ok: true;
      idempotentReplay: boolean;
      request: SnapshotCommissionRequestRecord;
    }
  | { ok: false; code: "no_pending_request" };

export interface CompleteSnapshotCommissionRequestInput {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  requestId: string;
  workerRunKey: string;
  status: Extract<SnapshotCommissionRequestStatus, "release_registered" | "activation_pending" | "failed">;
  registeredReleaseId?: string;
  errorCode?: string;
  errorMessage?: string;
}

export interface CompleteSnapshotCommissionRequestResult {
  ok: true;
  idempotentReplay: boolean;
  requestId: string;
  status: SnapshotCommissionRequestStatus;
  registeredReleaseId?: string;
  auditId?: string;
}

export async function createSnapshotCommissionRequest(
  input: CreateSnapshotCommissionRequestInput
): Promise<CreateSnapshotCommissionRequestResult> {
  const client = resolveClient(input);
  const ownsClient = ownsConnection(input, client);

  try {
    const response = await client.query<{ result: Record<string, unknown> }>(
      `
        select ingestion_platform.create_snapshot_commission_request(
          $1,
          $2,
          $3,
          $4::jsonb,
          $5::jsonb,
          $6,
          $7,
          $8,
          $9
        ) as result
      `,
      [
        input.projectKey,
        input.planKey,
        input.sourceKey,
        JSON.stringify(input.countries),
        JSON.stringify(input.categories),
        input.maxRowsPerScope,
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
      status: "requested"
    };
  } finally {
    if (ownsClient) {
      await (client as Client).end();
    }
  }
}

export async function claimSnapshotCommissionRequest(
  input: ClaimSnapshotCommissionRequestInput
): Promise<ClaimSnapshotCommissionRequestResult> {
  const client = resolveClient(input);
  const ownsClient = ownsConnection(input, client);

  try {
    const response = await client.query<{ result: Record<string, unknown> }>(
      `
        select ingestion_platform.claim_snapshot_commission_request($1, $2) as result
      `,
      [input.workerId, input.workerRunKey]
    );
    const result = response.rows[0]?.result ?? {};
    if (result.ok !== true) {
      return { ok: false, code: "no_pending_request" };
    }
    return {
      ok: true,
      idempotentReplay: result.idempotentReplay === true,
      request: mapClaimResult(result)
    };
  } finally {
    if (ownsClient) {
      await (client as Client).end();
    }
  }
}

export async function completeSnapshotCommissionRequest(
  input: CompleteSnapshotCommissionRequestInput
): Promise<CompleteSnapshotCommissionRequestResult> {
  const client = resolveClient(input);
  const ownsClient = ownsConnection(input, client);

  try {
    const response = await client.query<{ result: Record<string, unknown> }>(
      `
        select ingestion_platform.complete_snapshot_commission_request(
          $1::bigint,
          $2,
          $3,
          $4,
          $5,
          $6
        ) as result
      `,
      [
        input.requestId,
        input.workerRunKey,
        input.status,
        input.registeredReleaseId ?? null,
        input.errorCode ?? null,
        input.errorMessage ?? null
      ]
    );
    const result = response.rows[0]?.result ?? {};
    return {
      ok: true,
      idempotentReplay: result.idempotentReplay === true,
      requestId: String(result.requestId),
      status: String(result.status) as SnapshotCommissionRequestStatus,
      registeredReleaseId:
        typeof result.registeredReleaseId === "string" ? result.registeredReleaseId : undefined,
      auditId: typeof result.auditId === "string" ? result.auditId : undefined
    };
  } finally {
    if (ownsClient) {
      await (client as Client).end();
    }
  }
}

export async function loadLatestSnapshotCommissionRequest(input: {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  projectKey: string;
  planKey: string;
}): Promise<SnapshotCommissionRequestRecord | null> {
  const client = resolveClient(input);
  const ownsClient = ownsConnection(input, client);

  try {
    const response = await client.query<CommissionRow>(
      `
        select
          r.id::text as request_id,
          p.project_key,
          bp.plan_key,
          r.source_key,
          r.status,
          r.countries,
          r.categories,
          r.max_rows_per_scope,
          r.audit_reason,
          r.requested_by_type,
          r.requested_by_id,
          r.requested_at,
          r.claimed_at,
          r.claimed_by_id,
          r.worker_run_key,
          r.registered_release_id,
          r.error_code,
          r.error_message,
          r.completed_at
        from ingestion_platform.ingestion_snapshot_commission_requests r
        join ingestion_platform.ingestion_projects p on p.id = r.project_id
        join ingestion_platform.ingestion_batch_plans bp on bp.id = r.batch_plan_id
        where p.project_key = $1 and bp.plan_key = $2
        order by r.requested_at desc, r.id desc
        limit 1
      `,
      [input.projectKey, input.planKey]
    );
    const row = response.rows[0];
    return row ? mapCommissionRow(row) : null;
  } finally {
    if (ownsClient) {
      await (client as Client).end();
    }
  }
}

export async function hasActiveSnapshotCommissionRequest(input: {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  projectKey: string;
  planKey: string;
}): Promise<boolean> {
  const client = resolveClient(input);
  const ownsClient = ownsConnection(input, client);

  try {
    const response = await client.query<{ exists: boolean }>(
      `
        select exists (
          select 1
          from ingestion_platform.ingestion_snapshot_commission_requests r
          join ingestion_platform.ingestion_projects p on p.id = r.project_id
          join ingestion_platform.ingestion_batch_plans bp on bp.id = r.batch_plan_id
          where p.project_key = $1
            and bp.plan_key = $2
            and r.status = any($3::text[])
        ) as exists
      `,
      [input.projectKey, input.planKey, SNAPSHOT_COMMISSION_ACTIVE_STATUSES]
    );
    return response.rows[0]?.exists === true;
  } finally {
    if (ownsClient) {
      await (client as Client).end();
    }
  }
}

interface CommissionRow extends Record<string, unknown> {
  request_id: string;
  project_key: string;
  plan_key: string;
  source_key: string;
  status: string;
  countries: string[];
  categories: string[];
  max_rows_per_scope: number;
  audit_reason: string;
  requested_by_type: string;
  requested_by_id: string;
  requested_at: string | Date;
  claimed_at?: string | Date | null;
  claimed_by_id?: string | null;
  worker_run_key?: string | null;
  registered_release_id?: string | null;
  error_code?: string | null;
  error_message?: string | null;
  completed_at?: string | Date | null;
}

function mapCommissionRow(row: CommissionRow): SnapshotCommissionRequestRecord {
  const status = String(row.status);
  if (!isSnapshotCommissionRequestStatus(status)) {
    throw new Error(`Unknown snapshot commission status "${status}".`);
  }
  return {
    requestId: row.request_id,
    projectKey: row.project_key,
    planKey: row.plan_key,
    sourceKey: row.source_key,
    status,
    countries: Array.isArray(row.countries) ? row.countries.map(String) : [],
    categories: Array.isArray(row.categories) ? row.categories.map(String) : [],
    maxRowsPerScope: Number(row.max_rows_per_scope),
    auditReason: row.audit_reason,
    requestedByType: row.requested_by_type,
    requestedById: row.requested_by_id,
    requestedAt: toIsoString(row.requested_at),
    claimedAt: row.claimed_at ? toIsoString(row.claimed_at) : undefined,
    claimedById: row.claimed_by_id ?? undefined,
    workerRunKey: row.worker_run_key ?? undefined,
    registeredReleaseId: row.registered_release_id ?? undefined,
    errorCode: row.error_code ?? undefined,
    errorMessage: row.error_message ?? undefined,
    completedAt: row.completed_at ? toIsoString(row.completed_at) : undefined
  };
}

function mapClaimResult(result: Record<string, unknown>): SnapshotCommissionRequestRecord {
  const status = String(result.status);
  if (!isSnapshotCommissionRequestStatus(status)) {
    throw new Error(`Unknown snapshot commission status "${status}".`);
  }
  return {
    requestId: String(result.requestId),
    projectKey: String(result.projectKey),
    planKey: String(result.planKey),
    sourceKey: String(result.sourceKey),
    status,
    countries: Array.isArray(result.countries) ? result.countries.map(String) : [],
    categories: Array.isArray(result.categories) ? result.categories.map(String) : [],
    maxRowsPerScope: Number(result.maxRowsPerScope),
    auditReason: "",
    requestedByType: "operator",
    requestedById: "",
    requestedAt: new Date(0).toISOString(),
    registeredReleaseId:
      typeof result.registeredReleaseId === "string" ? result.registeredReleaseId : undefined
  };
}

function resolveClient(input: {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
}): SnapshotCommissionPgClientLike {
  const client =
    input.client ??
    (input.connectionString ? new Client({ connectionString: input.connectionString }) : null);
  if (!client) {
    throw new Error("Control database connection is required.");
  }
  return client;
}

function ownsConnection(
  input: { connectionString?: string; client?: SnapshotCommissionPgClientLike },
  client: SnapshotCommissionPgClientLike
): boolean {
  return Boolean(input.connectionString && !input.client && client instanceof Client);
}

function toIsoString(value: string | Date): string {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}
