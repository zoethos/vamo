export type ApprovalEnvelopeDerived = {
  selectedScopes: number;
  expectedPackages: number;
  expectedTargetWrites: number;
  maxUnits: number;
  maxPackages: number;
  maxTargetWrites: number;
  rampCapLabel: string | null;
  exceedsRampCap: boolean;
};

export type ApprovalEnvelopeOverride = {
  maxUnits: number;
  maxPackages: number;
  maxTargetWrites: number;
};

export function deriveProductionPackageApprovalEnvelope(input: {
  selectedScopes: number;
  expectedTargetWrites: number;
  hasPriorDeliveredPackage: boolean;
  override?: ApprovalEnvelopeOverride | null;
}): ApprovalEnvelopeDerived {
  const selectedScopes = input.selectedScopes;
  const expectedPackages = selectedScopes;
  const expectedTargetWrites = input.expectedTargetWrites;
  const derivedCaps = {
    maxUnits: Math.max(selectedScopes, 0) || 0,
    maxPackages: Math.max(expectedPackages, 0) || 0,
    maxTargetWrites: Math.max(expectedTargetWrites, 0) || 0
  };
  const caps = input.override ?? derivedCaps;
  const rampCapLabel = input.hasPriorDeliveredPackage
    ? null
    : "First live wave: max 1 unit, 1 package (server enforced)";
  const exceedsRampCap = !input.hasPriorDeliveredPackage && selectedScopes > 1;

  return {
    selectedScopes,
    expectedPackages,
    expectedTargetWrites,
    maxUnits: caps.maxUnits,
    maxPackages: caps.maxPackages,
    maxTargetWrites: caps.maxTargetWrites,
    rampCapLabel,
    exceedsRampCap
  };
}

export function approvalEnvelopeOverrideWarning(
  envelope: ApprovalEnvelopeDerived,
  override: ApprovalEnvelopeOverride
): string | undefined {
  if (override.maxUnits < envelope.selectedScopes) {
    return "Max units override is lower than selected scopes; the server will reject approval.";
  }
  if (override.maxPackages < envelope.expectedPackages) {
    return "Max packages override is lower than expected packages; the server will reject approval.";
  }
  if (override.maxTargetWrites < envelope.expectedTargetWrites) {
    return "Max target writes override is lower than expected target writes; the server will reject approval.";
  }
  return undefined;
}

export type ApprovalOperationPhase = "idle" | "recording" | "refreshing";

export function approvalButtonLabel(
  phase: ApprovalOperationPhase,
  selectedCount: number
): string {
  if (phase === "recording") {
    return "Recording approval…";
  }
  if (phase === "refreshing") {
    return "Refreshing delivery status…";
  }
  if (selectedCount > 0) {
    return `Approve selected package wave (${selectedCount})`;
  }
  return "Approve selected package wave";
}

export function approvalButtonDisabledReason(input: {
  contextDisabledReason?: string;
  phase: ApprovalOperationPhase;
  eligibleCount: number;
  selectedCount: number;
  auditReason: string;
  envelope: ApprovalEnvelopeDerived;
  overrideWarning?: string;
}): string | undefined {
  if (input.contextDisabledReason) {
    return input.contextDisabledReason;
  }
  if (input.phase === "recording") {
    return "Recording approval for the selected package wave.";
  }
  if (input.phase === "refreshing") {
    return "Refreshing delivery status after approval.";
  }
  if (input.eligibleCount === 0) {
    return "No staging-verified scopes with valid simulation and staging evidence are available.";
  }
  if (input.selectedCount === 0) {
    return "Select at least one eligible staging-verified scope.";
  }
  if (!input.auditReason.trim()) {
    return "Enter an audit reason before approving.";
  }
  if (input.envelope.exceedsRampCap) {
    return "First live production package wave is capped at 1 unit and 1 package. Select one scope or wait until a prior wave has delivered.";
  }
  if (input.overrideWarning) {
    return input.overrideWarning;
  }
  if (input.envelope.maxUnits < 1 || input.envelope.maxPackages < 1 || input.envelope.maxTargetWrites < 1) {
    return "Approval envelope caps must be positive integers.";
  }
  return undefined;
}

export type ApplyPreflightPhase = "idle" | "checking";
export type ApplyOperationPhase = "idle" | "applying" | "refreshing" | "completed";

export function applyButtonLabel(input: {
  preflightPhase: ApplyPreflightPhase;
  applyPhase: ApplyOperationPhase;
  selectedCount: number;
}): string {
  if (input.preflightPhase === "checking") {
    return "Checking apply preflight…";
  }
  if (input.applyPhase === "applying") {
    return `Applying ${input.selectedCount} package${input.selectedCount === 1 ? "" : "s"} to Vamo…`;
  }
  if (input.applyPhase === "refreshing") {
    return "Refreshing delivery status…";
  }
  if (input.applyPhase === "completed") {
    return "Completed";
  }
  return `Apply selected packages to Vamo (${input.selectedCount})`;
}

export function applyButtonDisabledReason(input: {
  contextDisabledReason?: string;
  preflightPhase: ApplyPreflightPhase;
  applyPhase: ApplyOperationPhase;
  inFlight: boolean;
  selectedCount: number;
  auditReason: string;
  preflightBlocks: string[];
  hasPreflight: boolean;
}): string | undefined {
  if (input.contextDisabledReason) {
    return input.contextDisabledReason;
  }
  if (input.inFlight || input.applyPhase === "applying" || input.applyPhase === "refreshing") {
    if (input.applyPhase === "applying") {
      return `Applying ${input.selectedCount} package${input.selectedCount === 1 ? "" : "s"} to Vamo. ${APPLY_DURATION_NOTE} ${APPLY_IN_FLIGHT_DO_NOT_RETRY}`;
    }
    if (input.applyPhase === "refreshing") {
      return "Refreshing delivery status after consumer apply.";
    }
    return "Batch apply is already running.";
  }
  if (input.selectedCount === 0) {
    return "Select at least one delivered package with pending apply items.";
  }
  if (input.preflightPhase === "checking") {
    return "Checking apply preflight for the selected packages.";
  }
  if (input.preflightBlocks.length > 0) {
    return "Resolve batch apply preflight blocks before continuing.";
  }
  if (!input.hasPreflight) {
    return "Waiting for batch apply preflight to finish.";
  }
  if (!input.auditReason.trim()) {
    return "Enter an audit reason before applying.";
  }
  return undefined;
}

export const APPLY_DURATION_NOTE =
  "This may take several seconds for current batches; larger batches will move to tracked background jobs.";

export const APPLY_IN_FLIGHT_DO_NOT_RETRY =
  "Do not refresh or retry unless the operation reports failure.";

export const APPLY_AMBIGUOUS_RESULT_MESSAGE =
  "The apply request did not return a final result. The operation may still have completed. Refresh delivery telemetry before retrying.";

/** Client-side guard for synchronous batch apply; does not cancel server work. */
export const APPLY_REQUEST_TIMEOUT_MS = 10 * 60 * 1000;

export function formatApplyElapsedLabel(elapsedMs: number): string {
  const totalSeconds = Math.max(0, Math.floor(elapsedMs / 1000));
  if (totalSeconds < 60) {
    return `${totalSeconds || 1}s elapsed`;
  }
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return seconds > 0 ? `${minutes}m ${seconds}s elapsed` : `${minutes}m elapsed`;
}

export function applyInFlightStatusLines(input: {
  selectedCount: number;
  elapsedMs: number;
}): {
  headline: string;
  durationLine: string;
  guidanceLine: string;
} {
  return {
    headline: `Applying ${input.selectedCount} package${input.selectedCount === 1 ? "" : "s"} to Vamo…`,
    durationLine: `${formatApplyElapsedLabel(input.elapsedMs)} · ${APPLY_DURATION_NOTE}`,
    guidanceLine: APPLY_IN_FLIGHT_DO_NOT_RETRY
  };
}

export function summarizeBatchApplyStopOnFailure(input: {
  selectedPackageIds: string[];
  failedPackageId?: string;
  skippedAppliedPackageIds?: string[];
}): {
  appliedCount: number;
  failedPackageId?: string;
  notAttemptedCount: number;
  skippedCount: number;
} {
  const skippedCount = input.skippedAppliedPackageIds?.length ?? 0;
  if (!input.failedPackageId) {
    return {
      appliedCount: 0,
      notAttemptedCount: input.selectedPackageIds.length,
      skippedCount
    };
  }
  const failedIndex = input.selectedPackageIds.indexOf(input.failedPackageId);
  if (failedIndex < 0) {
    return {
      appliedCount: 0,
      failedPackageId: input.failedPackageId,
      notAttemptedCount: input.selectedPackageIds.length,
      skippedCount
    };
  }
  return {
    appliedCount: failedIndex,
    failedPackageId: input.failedPackageId,
    notAttemptedCount: Math.max(input.selectedPackageIds.length - failedIndex - 1, 0),
    skippedCount
  };
}

export function isAmbiguousBatchApplyResponse(input: {
  status: number;
  payload:
    | {
        ok?: boolean;
        decision?: string;
        blocks?: unknown[];
        error?: string;
      }
    | null
    | undefined;
}): boolean {
  if (!input.payload) {
    return true;
  }
  if (input.payload.ok === true) {
    return false;
  }
  if (input.payload.decision === "blocked" || input.payload.decision === "failed") {
    return false;
  }
  if (Array.isArray(input.payload.blocks) && input.payload.blocks.length > 0) {
    return false;
  }
  if (input.status === 408) {
    return true;
  }
  if (input.status >= 400 && input.status < 500 && input.payload.error) {
    return false;
  }
  return input.status >= 500 || !input.payload.error;
}
