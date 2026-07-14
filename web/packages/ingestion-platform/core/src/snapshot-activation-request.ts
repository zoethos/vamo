/**
 * Operator-confirmed snapshot activation request model (IP-18.8.14).
 *
 * A request is distinct from acquisition commissioning. It authorizes a
 * trusted worker to run the already-verified activation path for one release.
 */
export const SNAPSHOT_ACTIVATION_REQUEST_CONFIRMATION_STATE = "request_activation" as const;

export const SNAPSHOT_ACTIVATION_REQUEST_STATUSES = [
  "requested",
  "running",
  "activated",
  "failed"
] as const;

export type SnapshotActivationRequestStatus =
  (typeof SNAPSHOT_ACTIVATION_REQUEST_STATUSES)[number];

export const SNAPSHOT_ACTIVATION_REQUEST_ACTIVE_STATUSES = [
  "requested",
  "running"
] as const satisfies readonly SnapshotActivationRequestStatus[];

export const SNAPSHOT_ACTIVATION_REQUEST_DEFAULT_LEASE_SECONDS = 30 * 60;

export interface SnapshotActivationRequestRecord {
  requestId: string;
  projectKey: string;
  planKey: string;
  commissionRequestId: string;
  releaseId: string;
  status: SnapshotActivationRequestStatus;
  auditReason: string;
  requestedByType: string;
  requestedById: string;
  requestedAt: string;
  claimedAt?: string;
  claimedById?: string;
  workerRunKey?: string;
  claimExpiresAt?: string;
  attemptCount?: number;
  bindingId?: string;
  activationAuditId?: string;
  errorCode?: string;
  errorMessage?: string;
  completedAt?: string;
}

export interface SnapshotActivationRequestCreateInput {
  projectKey: string;
  auditReason: string;
  confirmedState: string;
}

export function isSnapshotActivationRequestStatus(
  value: string
): value is SnapshotActivationRequestStatus {
  return (SNAPSHOT_ACTIVATION_REQUEST_STATUSES as readonly string[]).includes(value);
}

export function canTransitionSnapshotActivationRequestStatus(
  from: SnapshotActivationRequestStatus,
  to: SnapshotActivationRequestStatus
): boolean {
  if (from === to) {
    return true;
  }
  if (from === "requested") {
    return to === "running" || to === "failed";
  }
  return from === "running" && (to === "activated" || to === "failed");
}

export function parseSnapshotActivationRequestCreate(
  body: unknown
):
  | { ok: true; request: SnapshotActivationRequestCreateInput }
  | { ok: false; error: string; code: string } {
  if (!body || typeof body !== "object") {
    return { ok: false, error: "Request body must be a JSON object.", code: "invalid_body" };
  }

  const value = body as Record<string, unknown>;
  const projectKey = readString(value.projectKey);
  const auditReason = readString(value.auditReason);
  const confirmedState = readString(value.confirmedState);

  if (!projectKey) {
    return { ok: false, error: "projectKey is required.", code: "project_key_required" };
  }
  if (!auditReason) {
    return { ok: false, error: "auditReason is required.", code: "audit_reason_required" };
  }
  if (confirmedState !== SNAPSHOT_ACTIVATION_REQUEST_CONFIRMATION_STATE) {
    return {
      ok: false,
      error: "confirmedState must match the activation confirmation token.",
      code: "confirmed_state_mismatch"
    };
  }

  return { ok: true, request: { projectKey, auditReason, confirmedState } };
}

function readString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}
