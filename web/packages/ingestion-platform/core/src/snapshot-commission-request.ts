/**
 * Snapshot release commissioning request model (IP-18.8.13).
 */
import { FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE } from "./fsq-acquisition-scope.js";
export const SNAPSHOT_COMMISSION_CONFIRMATION_STATE = "request_commission" as const;
export const SNAPSHOT_COMMISSION_REQUEST_STATUSES = [
  "requested",
  "running",
  "release_registered",
  "activation_pending",
  "failed"
] as const;
export type SnapshotCommissionRequestStatus =
  (typeof SNAPSHOT_COMMISSION_REQUEST_STATUSES)[number];
export const SNAPSHOT_COMMISSION_TERMINAL_STATUSES = [
  "activation_pending",
  "failed"
] as const satisfies readonly SnapshotCommissionRequestStatus[];
export const SNAPSHOT_COMMISSION_ACTIVE_STATUSES = [
  "requested",
  "running",
  "release_registered"
] as const satisfies readonly SnapshotCommissionRequestStatus[];
export const SNAPSHOT_COMMISSION_DEFAULT_LEASE_MS = 30 * 60 * 1000;
export interface SnapshotCommissionRequestRecord {
  requestId: string;
  projectKey: string;
  planKey: string;
  sourceKey: string;
  status: SnapshotCommissionRequestStatus;
  countries: string[];
  categories: string[];
  maxRowsPerScope: number;
  auditReason: string;
  requestedByType: string;
  requestedById: string;
  requestedAt: string;
  claimedAt?: string;
  claimedById?: string;
  workerRunKey?: string;
  claimExpiresAt?: string;
  attemptCount?: number;
  registeredReleaseId?: string;
  errorCode?: string;
  errorMessage?: string;
  completedAt?: string;
}
export interface SnapshotCommissionRequestCreateInput {
  projectKey: string;
  planKey: string;
  countries: readonly string[];
  categories: readonly string[];
  maxRowsPerScope?: number;
  auditReason: string;
  confirmedState: string;
}
export function isSnapshotCommissionRequestStatus(
  value: string
): value is SnapshotCommissionRequestStatus {
  return (SNAPSHOT_COMMISSION_REQUEST_STATUSES as readonly string[]).includes(value);
}
export function canTransitionSnapshotCommissionStatus(
  from: SnapshotCommissionRequestStatus,
  to: SnapshotCommissionRequestStatus
): boolean {
  if (from === to) {
    return true;
  }
  switch (from) {
    case "requested":
      return to === "running" || to === "failed";
    case "running":
      return to === "release_registered" || to === "activation_pending" || to === "failed";
    case "release_registered":
      return to === "activation_pending" || to === "failed";
    default:
      return false;
  }
}
export function parseSnapshotCommissionRequestCreate(
  body: unknown
):
  | { ok: true; request: SnapshotCommissionRequestCreateInput }
  | { ok: false; error: string; code?: string } {
  if (!body || typeof body !== "object") {
    return { ok: false, error: "Request body must be a JSON object.", code: "invalid_body" };
  }
  const value = body as Record<string, unknown>;
  const projectKey = readString(value.projectKey);
  const planKey = readString(value.planKey);
  const auditReason = readString(value.auditReason);
  const confirmedState = readString(value.confirmedState);
  const countries = readStringArray(value.countries);
  const categories = readStringArray(value.categories);
  const maxRowsPerScope = readPositiveInteger(value.maxRowsPerScope);
  if (!projectKey) {
    return { ok: false, error: "projectKey is required.", code: "project_key_required" };
  }
  if (!planKey) {
    return { ok: false, error: "planKey is required.", code: "plan_key_required" };
  }
  if (!auditReason) {
    return { ok: false, error: "auditReason is required.", code: "audit_reason_required" };
  }
  if (confirmedState !== SNAPSHOT_COMMISSION_CONFIRMATION_STATE) {
    return {
      ok: false,
      error: "confirmedState must match the commissioning confirmation token.",
      code: "confirmed_state_mismatch"
    };
  }
  if (countries.length === 0) {
    return { ok: false, error: "At least one country is required.", code: "countries_required" };
  }
  if (categories.length === 0) {
    return { ok: false, error: "At least one category is required.", code: "categories_required" };
  }
  return {
    ok: true,
    request: {
      projectKey,
      planKey,
      countries,
      categories,
      maxRowsPerScope: maxRowsPerScope ?? FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE,
      auditReason,
      confirmedState
    }
  };
}
function readString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}
function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((entry): entry is string => typeof entry === "string")
    .map((entry) => entry.trim().toLowerCase())
    .filter((entry) => entry.length > 0);
}
function readPositiveInteger(value: unknown): number | undefined {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }
  const parsed = typeof value === "number" ? value : Number.parseInt(String(value), 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}
