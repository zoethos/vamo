/**
 * Control-plane snapshot commission request adapter (IP-18.8.13).
 */
import { Client, type QueryResult } from "pg";
import { loadAutonomyPolicy, type AutonomyControlReadPgClientLike } from "./autonomy-control-read.js";
import { loadBatchQueueSnapshot, type BatchQueueControlReadPgClientLike } from "./batch-queue-control-read.js";
import { resolveAutonomyDrainBatchPlanKey } from "./batch-plan-selection.js";
import {
  evaluateSnapshotCommissionPlanResolution,
  type SnapshotCommissionPlanResolutionCode,
  type SnapshotCommissionPlanResolutionSource
} from "./snapshot-commission-plan-resolution.js";
import {
  extractPlanCommissionBounds,
  isSnapshotCommissionSupportedSourceKey,
  type SnapshotCommissionPlanContext
} from "./snapshot-commission-plan-context.js";
import { snapshotCommissionOperatorErrorForCode } from "./snapshot-commission-errors.js";
import { createBoundedPostgresReadClientConfig } from "./postgres-read-timeouts.js";
import {
  isSnapshotCommissionRequestStatus,
  SNAPSHOT_COMMISSION_ACTIVE_STATUSES,
  SNAPSHOT_COMMISSION_DEFAULT_LEASE_SECONDS,
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
  sourceKey: string;
}
export interface ClaimSnapshotCommissionRequestInput {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  workerId: string;
  workerRunKey: string;
  leaseSeconds?: number;
}
export type ClaimSnapshotCommissionRequestResult =
  | {
      ok: true;
      idempotentReplay: boolean;
      leaseReclaimed?: boolean;
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
export async function loadSnapshotCommissionPlanContext(input: {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  projectKey: string;
  planKey: string;
}): Promise<SnapshotCommissionPlanContext | null> {
  const { client, ownedClient } = await openClient(input, "read");
  try {
    const response = await client.query<PlanContextRow>(
      `
        select
          p.project_key,
          bp.plan_key,
          bp.source_key,
          bp.status as plan_status,
          bp.spec
        from ingestion_platform.ingestion_batch_plans bp
        join ingestion_platform.ingestion_projects p on p.id = bp.project_id
        where p.project_key = $1 and bp.plan_key = $2
        limit 1
      `,
      [input.projectKey, input.planKey]
    );
    const row = response.rows[0];
    if (!row) {
      return null;
    }
    const bounds = extractPlanCommissionBounds(row.spec ?? {});
    return {
      projectKey: row.project_key,
      planKey: row.plan_key,
      sourceKey: row.source_key,
      planStatus: row.plan_status,
      allowedCountries: bounds.allowedCountries,
      allowedCategories: bounds.allowedCategories,
      maxRowsPerScopeLimit: bounds.maxRowsPerScopeLimit
    };
  } finally {
    await closeClient(ownedClient);
  }
}

export type LoadCommissionedSnapshotPlanContextResult =
  | {
      ok: true;
      context: SnapshotCommissionPlanContext;
      planSource: SnapshotCommissionPlanResolutionSource;
    }
  | {
      ok: false;
      code: SnapshotCommissionPlanResolutionCode;
    };

export async function loadCommissionedSnapshotPlanContext(input: {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  projectKey: string;
}): Promise<LoadCommissionedSnapshotPlanContextResult> {
  const { client, ownedClient } = await openClient(input, "read");

  try {
    const readClient = client as SnapshotCommissionPgClientLike &
      AutonomyControlReadPgClientLike &
      BatchQueueControlReadPgClientLike;

    const policy = await loadAutonomyPolicy(readClient, {
      projectKey: input.projectKey
    });
    const policyBatchPlanKey = policy
      ? resolveAutonomyDrainBatchPlanKey({ policy, batchPlanKey: undefined })
      : undefined;

    const queueSnapshot = await loadBatchQueueSnapshot({
      client: readClient,
      projectKey: input.projectKey
    });

    const resolution = evaluateSnapshotCommissionPlanResolution({
      policyBatchPlanKey,
      queuePlanKey: queueSnapshot?.planId
    });
    if (!resolution.ok) {
      return resolution;
    }

    const context = await loadSnapshotCommissionPlanContext({
      client: readClient,
      projectKey: input.projectKey,
      planKey: resolution.planKey
    });
    if (!context) {
      return { ok: false, code: "plan_not_found" };
    }

    return {
      ok: true,
      context,
      planSource: resolution.source
    };
  } finally {
    await closeClient(ownedClient);
  }
}

export async function findSnapshotReleaseIdForCommissionRequest(input: {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  projectKey: string;
  requestId: string;
}): Promise<string | null> {
  const { client, ownedClient } = await openClient(input, "read");
  try {
    const response = await client.query<{ release_id: string }>(
      `
        select r.release_id
        from ingestion_platform.ingestion_snapshot_releases r
        join ingestion_platform.ingestion_projects p on p.id = r.project_id
        where p.project_key = $1
          and r.metadata->>'commissionRequestId' = $2
        order by r.created_at desc, r.id desc
        limit 1
      `,
      [input.projectKey, input.requestId]
    );
    return response.rows[0]?.release_id ?? null;
  } finally {
    await closeClient(ownedClient);
  }
}
export async function createSnapshotCommissionRequest(
  input: CreateSnapshotCommissionRequestInput
): Promise<CreateSnapshotCommissionRequestResult> {
  const { client, ownedClient } = await openClient(input, "write");
  try {
    const response = await client.query<{ result: Record<string, unknown> }>(
      `
        select ingestion_platform.create_snapshot_commission_request(
          $1,
          $2,
          $3::jsonb,
          $4::jsonb,
          $5,
          $6,
          $7,
          $8
        ) as result
      `,
      [
        input.projectKey,
        input.planKey,
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
      status: "requested",
      sourceKey: String(result.sourceKey)
    };
  } finally {
    await closeClient(ownedClient);
  }
}
export async function claimSnapshotCommissionRequest(
  input: ClaimSnapshotCommissionRequestInput
): Promise<ClaimSnapshotCommissionRequestResult> {
  const { client, ownedClient } = await openClient(input, "write");
  const leaseSeconds = Math.max(
    1,
    input.leaseSeconds ?? SNAPSHOT_COMMISSION_DEFAULT_LEASE_SECONDS
  );
  try {
    const response = await client.query<{ result: Record<string, unknown> }>(
      `
        select ingestion_platform.claim_snapshot_commission_request($1, $2, $3) as result
      `,
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
  } finally {
    await closeClient(ownedClient);
  }
}
export async function completeSnapshotCommissionRequest(
  input: CompleteSnapshotCommissionRequestInput
): Promise<CompleteSnapshotCommissionRequestResult> {
  const { client, ownedClient } = await openClient(input, "write");
  const safeErrorMessage =
    input.status === "failed" && input.errorCode
      ? snapshotCommissionOperatorErrorForCode(input.errorCode)
      : input.errorMessage ?? null;
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
        safeErrorMessage
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
    await closeClient(ownedClient);
  }
}
export async function loadLatestSnapshotCommissionRequest(input: {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  projectKey: string;
  planKey: string;
}): Promise<SnapshotCommissionRequestRecord | null> {
  const { client, ownedClient } = await openClient(input, "read");
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
          r.claim_expires_at,
          r.attempt_count,
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
    await closeClient(ownedClient);
  }
}
export async function hasActiveSnapshotCommissionRequest(input: {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  projectKey: string;
  planKey: string;
}): Promise<boolean> {
  const { client, ownedClient } = await openClient(input, "read");
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
    await closeClient(ownedClient);
  }
}
export function assertCommissionPlanIsCommissionable(
  plan: SnapshotCommissionPlanContext
): { ok: true } | { ok: false; code: string; error: string } {
  if (plan.planStatus !== "active") {
    return {
      ok: false,
      code: "plan_not_active",
      error: snapshotCommissionOperatorErrorForCode("plan_not_active")
    };
  }
  if (!isSnapshotCommissionSupportedSourceKey(plan.sourceKey)) {
    return {
      ok: false,
      code: "unsupported_source_key",
      error: snapshotCommissionOperatorErrorForCode("unsupported_source_key")
    };
  }
  return { ok: true };
}
interface PlanContextRow extends Record<string, unknown> {
  project_key: string;
  plan_key: string;
  source_key: string;
  plan_status: string;
  spec: Record<string, unknown>;
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
  claim_expires_at?: string | Date | null;
  attempt_count?: number | null;
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
    claimExpiresAt: row.claim_expires_at ? toIsoString(row.claim_expires_at) : undefined,
    attemptCount: row.attempt_count ?? undefined,
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
      typeof result.registeredReleaseId === "string" ? result.registeredReleaseId : undefined,
    attemptCount: typeof result.attemptCount === "number" ? result.attemptCount : undefined,
    claimExpiresAt:
      typeof result.claimExpiresAt === "string" || result.claimExpiresAt instanceof Date
        ? toIsoString(result.claimExpiresAt as string | Date)
        : undefined
  };
}
async function openClient(
  input: {
  connectionString?: string;
  client?: SnapshotCommissionPgClientLike;
  },
  mode: "read" | "write"
): Promise<{ client: SnapshotCommissionPgClientLike; ownedClient?: Client }> {
  if (input.client) {
    return { client: input.client };
  }
  if (!input.connectionString) {
    throw new Error("Control database connection is required.");
  }
  const ownedClient = new Client(
    mode === "read"
      ? createBoundedPostgresReadClientConfig(input.connectionString)
      : { connectionString: input.connectionString }
  );
  await ownedClient.connect();
  return { client: ownedClient, ownedClient };
}

async function closeClient(ownedClient?: Client): Promise<void> {
  if (ownedClient) {
    await ownedClient.end();
  }
}
function toIsoString(value: string | Date): string {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}
