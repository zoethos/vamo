/**
 * Safe operator presenter for snapshot release commissioning (IP-18.8.13).
 */

import type { SnapshotCommissionRequestRecord, SnapshotCommissionRequestStatus } from "./snapshot-commission-request.js";
import { presentSnapshotCommissionOperatorError } from "./snapshot-commission-errors.js";

export interface SnapshotCommissionCardPresentation {
  hasRequest: boolean;
  status: SnapshotCommissionRequestStatus | "none";
  statusLabel: string;
  tone: "neutral" | "info" | "good" | "watch" | "danger";
  title: string;
  description: string;
  scopeSummary: string;
  nextHumanAction: string;
  recoveryHint?: string;
  requestId?: string;
  registeredReleaseId?: string;
  errorCode?: string;
  errorMessage?: string;
  failureTelemetry?: {
    traceId: string;
    stageLabel: string;
    classificationLabel: string;
    errorFingerprint?: string;
    sourceErrorCode?: string;
  };
  requestedAt?: string;
  requestedById?: string;
  canCreateRequest: boolean;
  confirmationState: string;
}

export function presentSnapshotCommissionCard(input: {
  request?: SnapshotCommissionRequestRecord | null;
  hasActiveRequest: boolean;
  defaultSourceKey: string;
  defaultCountries: string[];
  defaultCategories: string[];
  defaultMaxRowsPerScope: number;
  sourceTaxonomyReady?: boolean;
}): SnapshotCommissionCardPresentation {
  const request = input.request ?? null;
  if (!request) {
    const sourceTaxonomyReady = input.sourceTaxonomyReady !== false;
    return {
      hasRequest: false,
      status: "none",
      statusLabel: "No request",
      tone: "neutral",
      title: "Source release commissioning",
      description: sourceTaxonomyReady
        ? "Request a bounded FSQ snapshot acquisition for a trusted worker. The console never calls the provider directly."
        : "The active plan needs its published source mapping before bounded FSQ acquisition can be requested.",
      scopeSummary: formatScopeSummary({
        sourceKey: input.defaultSourceKey,
        countries: input.defaultCountries,
        categories: input.defaultCategories,
        maxRowsPerScope: input.defaultMaxRowsPerScope
      }),
      nextHumanAction: sourceTaxonomyReady
        ? "Submit a commissioning request with audit reason and fresh MFA step-up. A trusted worker executes acquisition later."
        : "Refresh the published plan contract first. This preserves all existing queue and delivery evidence.",
      canCreateRequest: !input.hasActiveRequest && sourceTaxonomyReady,
      confirmationState: "request_commission"
    };
  }

  const statusPresentation = presentCommissionStatus(request.status);
  return {
    hasRequest: true,
    status: request.status,
    statusLabel: statusPresentation.label,
    tone: statusPresentation.tone,
    title: "Source release commissioning",
    description: statusPresentation.description,
    scopeSummary: formatScopeSummary(request),
    nextHumanAction: statusPresentation.nextHumanAction,
    recoveryHint: statusPresentation.recoveryHint,
    requestId: request.requestId,
    registeredReleaseId: request.registeredReleaseId,
    errorCode: request.errorCode,
    errorMessage: presentSnapshotCommissionOperatorError(request.errorCode, request.errorMessage),
    failureTelemetry: presentFailureTelemetry(request.failureTelemetry),
    requestedAt: request.requestedAt,
    requestedById: request.requestedById,
    // A failed request is terminal and remains as evidence, but it must not
    // prevent the operator from recording a fresh bounded retry.
    canCreateRequest: request.status === "failed" && !input.hasActiveRequest,
    confirmationState: "request_commission"
  };
}

function presentCommissionStatus(status: SnapshotCommissionRequestStatus): {
  label: string;
  tone: SnapshotCommissionCardPresentation["tone"];
  description: string;
  nextHumanAction: string;
  recoveryHint?: string;
} {
  switch (status) {
    case "requested":
      return {
        label: "Requested",
        tone: "info",
        description: "The commissioning request is queued for a trusted worker.",
        nextHumanAction:
          "Start the protected commissioning worker workflow for this control environment, then keep this page open for status updates.",
        recoveryHint:
          "The Console checks this request while it is active. If it does not begin running, verify the protected job workflow and control-plane connectivity."
      };
    case "running":
      return {
        label: "Running",
        tone: "info",
        description: "A trusted worker is executing bounded FSQ acquisition.",
        nextHumanAction: "Wait for acquisition to finish. Do not submit another request for this plan.",
        recoveryHint:
          "The Console refreshes this status automatically. If it persists, inspect the protected worker log for this control environment and retry only after failure recovery."
      };
    case "release_registered":
      return {
        label: "Release registered",
        tone: "watch",
        description: "Acquisition succeeded and the release was registered in the control plane.",
        nextHumanAction: "Wait for the worker to finalize commissioning as activation pending.",
        recoveryHint: "If this state stalls, rerun the trusted worker with the same run key for idempotent recovery."
      };
    case "activation_pending":
      return {
        label: "Activation pending",
        tone: "good",
        description: "The snapshot release is registered and ready for separate activation.",
        nextHumanAction:
          "Run the trusted ip18:snapshot-activate command with explicit confirmation when ready to bind the release.",
        recoveryHint: "Activation is never automatic from commissioning."
      };
    case "failed":
      return {
        label: "Failed",
        tone: "danger",
        description: "Commissioning failed before a release became activation-ready.",
        nextHumanAction:
          "Review the safe error summary, fix the underlying provider or scope issue, then submit a new commissioning request.",
        recoveryHint: "Failed requests remain auditable; they are not deleted automatically."
      };
  }
}

function formatScopeSummary(input: {
  sourceKey: string;
  countries: readonly string[];
  categories: readonly string[];
  maxRowsPerScope: number;
}): string {
  return `${input.sourceKey} · ${input.countries.join(", ")} · ${input.categories.join(", ")} · max ${input.maxRowsPerScope} rows/scope`;
}

export function toSnapshotCommissionRequestSummary(
  row: SnapshotCommissionRequestRecord
): Omit<SnapshotCommissionRequestRecord, "workerRunKey"> {
  return {
    requestId: row.requestId,
    projectKey: row.projectKey,
    planKey: row.planKey,
    sourceKey: row.sourceKey,
    status: row.status,
    countries: row.countries,
    categories: row.categories,
    maxRowsPerScope: row.maxRowsPerScope,
    auditReason: row.auditReason,
    requestedByType: row.requestedByType,
    requestedById: row.requestedById,
    requestedAt: row.requestedAt,
    claimedAt: row.claimedAt,
    claimedById: row.claimedById,
    registeredReleaseId: row.registeredReleaseId,
    errorCode: row.errorCode,
    errorMessage: presentSnapshotCommissionOperatorError(row.errorCode, row.errorMessage),
    failureTelemetry: row.failureTelemetry,
    completedAt: row.completedAt
  };
}

function presentFailureTelemetry(
  telemetry: SnapshotCommissionRequestRecord["failureTelemetry"]
): SnapshotCommissionCardPresentation["failureTelemetry"] {
  if (!telemetry) {
    return undefined;
  }
  if (
    !/^[A-Za-z0-9-]{1,128}$/.test(telemetry.traceId) ||
    !/^[a-z_]{1,64}$/.test(telemetry.stage) ||
    !/^[a-z0-9_-]{1,96}$/.test(telemetry.classification)
  ) {
    return undefined;
  }
  return {
    traceId: telemetry.traceId,
    stageLabel: formatTelemetryLabel(telemetry.stage),
    classificationLabel: formatTelemetryLabel(telemetry.classification),
    errorFingerprint:
      telemetry.errorFingerprint && /^[a-f0-9]{64}$/i.test(telemetry.errorFingerprint)
        ? telemetry.errorFingerprint
        : undefined,
    sourceErrorCode:
      telemetry.sourceErrorCode && /^[A-Za-z0-9_-]{1,32}$/.test(telemetry.sourceErrorCode)
        ? telemetry.sourceErrorCode
        : undefined
  };
}

function formatTelemetryLabel(value: string): string {
  return value
    .split(/[_-]+/)
    .filter(Boolean)
    .map((part) => `${part.slice(0, 1).toUpperCase()}${part.slice(1)}`)
    .join(" ");
}
