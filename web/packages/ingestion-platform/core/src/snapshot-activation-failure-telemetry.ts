/**
 * Safe, durable failure telemetry for the trusted snapshot activation worker.
 *
 * The control plane receives a trace reference and a one-way fingerprint only.
 * Raw artifact, database, and worker errors remain in protected worker logs.
 */
import { createHash, randomUUID } from "node:crypto";

import type { SnapshotActivationFailureTelemetry } from "./snapshot-activation-request.js";

export type SnapshotActivationFailureStage =
  | "artifact_store"
  | "release_registry"
  | "control_plane"
  | "activation"
  | "worker";

export function describeSnapshotActivationPreconditionFailure(input: {
  blocks: readonly string[];
}): SnapshotActivationFailureTelemetry {
  const classification = input.blocks.find((block) => /^[a-z0-9_]{1,96}$/.test(block))
    ?? "activation_precondition_blocked";
  return {
    traceId: randomUUID(),
    stage: stageForActivationFailure(classification),
    classification
  };
}

export function describeUnexpectedSnapshotActivationFailure(
  error: unknown
): SnapshotActivationFailureTelemetry {
  const details = readErrorDetails(error);
  return {
    traceId: randomUUID(),
    stage: stageForUnexpectedActivationFailure(details.message, details.sourceErrorCode),
    classification: classifyUnexpectedFailure(details.message, details.sourceErrorCode),
    errorFingerprint: fingerprintError(details),
    sourceErrorCode: details.sourceErrorCode
  };
}

export function stageForActivationFailure(value: string): SnapshotActivationFailureStage {
  if (value.startsWith("artifact_")) return "artifact_store";
  if (value.startsWith("release_")) return "release_registry";
  if (value.startsWith("batch_") || value.startsWith("queue_")) return "control_plane";
  return "activation";
}

function stageForUnexpectedActivationFailure(
  message: string,
  sourceErrorCode?: string
): SnapshotActivationFailureStage {
  const lower = message.toLowerCase();
  if (/(artifact|bundle|checksum|sha-?256)/.test(lower)) return "artifact_store";
  if (/(release|binding)/.test(lower)) return "release_registry";
  if (/(does not exist|undefined function|42883|42p01)/.test(lower) || sourceErrorCode === "42883" || sourceErrorCode === "42P01") {
    return "control_plane";
  }
  if (/(reconcil|activation)/.test(lower)) return "activation";
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
  if (typeof value !== "string") return undefined;
  const normalized = value.trim();
  return /^[A-Za-z0-9_-]{1,32}$/.test(normalized) ? normalized : undefined;
}

function classifyUnexpectedFailure(message: string, sourceErrorCode?: string): string {
  const lower = message.toLowerCase();
  if (/(certificate|self signed|unable to verify|ssl|tls)/.test(lower)) return "tls_trust_failure";
  if (/(permission denied|access denied|forbidden|unauthorized)/.test(lower)) return "access_denied";
  if (/(timed out|timeout|etimedout)/.test(lower)) return "network_timeout";
  if (/(econnrefused|enotfound|econnreset|network is unreachable)/.test(lower)) return "network_unavailable";
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
