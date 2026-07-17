/**
 * Trusted-worker failure telemetry for snapshot commissioning.
 *
 * The durable control-plane record contains only safe classifications and a
 * non-reversible fingerprint. Raw provider, storage, and database errors stay
 * in the trusted worker log correlated by traceId.
 */

import { createHash, randomUUID } from "node:crypto";

import type { SnapshotCommissionFailureTelemetry } from "./snapshot-commission-request.js";

export type SnapshotCommissionFailureStage =
  | "portal"
  | "artifact_store"
  | "release_registry"
  | "contract"
  | "intake"
  | "control_plane"
  | "worker";

export function describeSnapshotCommissionAcquisitionFailure(input: {
  errorCode: string;
  blocks?: readonly string[];
}): SnapshotCommissionFailureTelemetry {
  const classification = input.blocks?.[0] ?? input.errorCode;
  return {
    traceId: randomUUID(),
    stage: stageForCommissionFailure(classification),
    classification
  };
}

export function describeUnexpectedSnapshotCommissionFailure(
  error: unknown
): SnapshotCommissionFailureTelemetry {
  const details = readErrorDetails(error);
  return {
    traceId: randomUUID(),
    stage: "worker",
    classification: classifyUnexpectedFailure(details.message, details.sourceErrorCode),
    errorFingerprint: fingerprintError(details),
    sourceErrorCode: details.sourceErrorCode
  };
}

export function stageForCommissionFailure(value: string): SnapshotCommissionFailureStage {
  if (value.startsWith("portal_")) {
    return "portal";
  }
  if (value.startsWith("artifact_")) {
    return "artifact_store";
  }
  if (value.startsWith("release_registration")) {
    return "release_registry";
  }
  if (value.startsWith("source_mapping") || value.startsWith("source_plan")) {
    return "contract";
  }
  if (value.includes("rejected") || value.includes("intake")) {
    return "intake";
  }
  if (value.includes("completion") || value.includes("control")) {
    return "control_plane";
  }
  return "worker";
}

function readErrorDetails(error: unknown): {
  name: string;
  message: string;
  sourceErrorCode?: string;
} {
  if (!error || typeof error !== "object") {
    return { name: "UnknownError", message: String(error) };
  }
  const record = error as Record<string, unknown>;
  const sourceErrorCode = normalizeSourceErrorCode(record.code);
  return {
    name: typeof record.name === "string" ? record.name : "Error",
    message: typeof record.message === "string" ? record.message : String(error),
    sourceErrorCode
  };
}

function normalizeSourceErrorCode(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const normalized = value.trim();
  return /^[A-Za-z0-9_-]{1,32}$/.test(normalized) ? normalized : undefined;
}

function classifyUnexpectedFailure(message: string, sourceErrorCode?: string): string {
  const lower = message.toLowerCase();
  if (/(certificate|self signed|unable to verify|ssl|tls)/.test(lower)) {
    return "tls_trust_failure";
  }
  if (/(permission denied|access denied|forbidden|unauthorized)/.test(lower)) {
    return "access_denied";
  }
  if (/(timed out|timeout|etimedout)/.test(lower)) {
    return "network_timeout";
  }
  if (/(econnrefused|enotfound|econnreset|network is unreachable)/.test(lower)) {
    return "network_unavailable";
  }
  if (/(does not exist|undefined function|42883|42p01)/.test(lower) || sourceErrorCode === "42883" || sourceErrorCode === "42P01") {
    return "control_schema_missing";
  }
  return "unexpected_exception";
}

function fingerprintError(input: {
  name: string;
  message: string;
  sourceErrorCode?: string;
}): string {
  return createHash("sha256")
    .update(input.name)
    .update("\0")
    .update(input.sourceErrorCode ?? "")
    .update("\0")
    .update(input.message)
    .digest("hex");
}
