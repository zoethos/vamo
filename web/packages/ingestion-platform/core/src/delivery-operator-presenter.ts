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
      return `Applying ${input.selectedCount} package${input.selectedCount === 1 ? "" : "s"} to Vamo. This can take several seconds for current batches; larger batches will move to tracked background jobs.`;
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
  "This can take several seconds for current batches; larger batches will move to tracked background jobs.";
