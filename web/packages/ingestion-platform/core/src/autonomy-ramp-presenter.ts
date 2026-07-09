/**
 * Pure presenter for the autonomy ramp promotion card (IP-18.7.4 PR2).
 */

import type { AutonomyPolicyEnvelope } from "./autonomy-policy.js";
import type { AutonomyRampReadiness } from "./autonomy-ramp-control.js";
import {
  AUTONOMY_RAMP_MODES,
  AUTONOMY_RAMP_PROFILES,
  applyRampProfileToEnvelope,
  resolveAutonomyRamp,
  type AutonomyRampMode
} from "./autonomy-ramp-policy.js";

export interface AutonomyRampBoundsColumn {
  maxUnitsPerCycle: number;
  maxRowsPerCycle: number;
  maxCyclesPerDay: number;
  maxUnitsPerDay: number;
  maxRowsPerDay: number;
}

export interface AutonomyRampCardPresentation {
  currentMode: AutonomyRampMode;
  currentModeLabel: string;
  nextMode: AutonomyRampMode | null;
  nextModeLabel: string | null;
  demotionModes: Array<{ mode: AutonomyRampMode; label: string }>;
  ownerCeiling: AutonomyRampBoundsColumn;
  profileCaps: AutonomyRampBoundsColumn;
  effectiveBounds: AutonomyRampBoundsColumn;
  rampWarnings: string[];
  policyWithinProfile: boolean;
  readinessEvidence: Array<{ label: string; value: string }>;
  advisoryWarnings: string[];
  activeBlockerCount: number;
  blockerSummaries: Array<{ reason: string; count: number }>;
}

export function presentAutonomyRampCard(input: {
  policy: AutonomyPolicyEnvelope;
  readiness: AutonomyRampReadiness | null;
  blockerSummaries?: Array<{ reason: string; count: number }>;
  blockedUnitCount?: number;
}): AutonomyRampCardPresentation {
  const ramp = resolveAutonomyRamp(input.policy);
  const effective = applyRampProfileToEnvelope(input.policy);
  const nextMode = ramp.recommendedNextMode ?? null;

  return {
    currentMode: ramp.mode,
    currentModeLabel: ramp.label,
    nextMode,
    nextModeLabel: nextMode ? AUTONOMY_RAMP_PROFILES[nextMode].label : null,
    demotionModes: listDemotionModes(ramp.mode),
    ownerCeiling: toBoundsColumn(effective.ownerCeiling),
    profileCaps: toBoundsColumn(effective.profileCaps),
    effectiveBounds: toBoundsColumn({
      maxUnitsPerCycle: effective.effective.maxUnitsPerCycle,
      maxRowsPerCycle: effective.effective.maxRowsPerCycle,
      rollingLimits: effective.effective.rollingLimits
    }),
    rampWarnings: ramp.warnings,
    policyWithinProfile: ramp.policyWithinProfile,
    readinessEvidence: buildReadinessEvidence(input.readiness),
    advisoryWarnings: buildAdvisoryWarnings(input.readiness),
    activeBlockerCount:
      (input.blockerSummaries ?? []).reduce((sum, blocker) => sum + blocker.count, 0) +
      (input.blockedUnitCount ?? 0),
    blockerSummaries: input.blockerSummaries ?? []
  };
}

export function buildAdvisoryWarnings(readiness: AutonomyRampReadiness | null): string[] {
  if (!readiness) {
    return ["Readiness evidence is unavailable until the live control plane is connected."];
  }

  const warnings: string[] = [];
  const totalRuns =
    readiness.runs.advanced + readiness.runs.completed + readiness.runs.failed + readiness.runs.paused;

  if (totalRuns < 2) {
    warnings.push(
      "Fewer than two agent cycles have run in the current ramp mode — consider more bootstrap proof before widening."
    );
  }
  if (readiness.runs.failed > 0) {
    warnings.push(`${readiness.runs.failed} failed agent run(s) recorded since the current ramp mode began.`);
  }
  if (readiness.runs.paused > 0) {
    warnings.push(`${readiness.runs.paused} paused agent run(s) recorded since the current ramp mode began.`);
  }
  if (readiness.stagingCanarySucceededUnits === 0) {
    warnings.push("No staging-verified scopes yet — promotion widens simulation bounds only, not staging writes.");
  }

  return warnings;
}

function buildReadinessEvidence(readiness: AutonomyRampReadiness | null) {
  if (!readiness) {
    return [{ label: "Readiness", value: "Unavailable" }];
  }

  return [
    { label: "Agent runs since mode change", value: String(readiness.runs.advanced + readiness.runs.completed) },
    { label: "Failed runs", value: String(readiness.runs.failed) },
    { label: "Paused runs", value: String(readiness.runs.paused) },
    { label: "Staging verified scopes", value: String(readiness.stagingCanarySucceededUnits) }
  ];
}

function listDemotionModes(currentMode: AutonomyRampMode) {
  const currentIndex = AUTONOMY_RAMP_MODES.indexOf(currentMode);
  return AUTONOMY_RAMP_MODES.slice(0, currentIndex).map((mode) => ({
    mode,
    label: AUTONOMY_RAMP_PROFILES[mode].label
  }));
}

function toBoundsColumn(input: {
  maxUnitsPerCycle: number;
  maxRowsPerCycle: number;
  rollingLimits: Record<string, unknown>;
}): AutonomyRampBoundsColumn {
  return {
    maxUnitsPerCycle: input.maxUnitsPerCycle,
    maxRowsPerCycle: input.maxRowsPerCycle,
    maxCyclesPerDay: numberOrZero(input.rollingLimits.maxCyclesPerDay),
    maxUnitsPerDay: numberOrZero(input.rollingLimits.maxUnitsPerDay),
    maxRowsPerDay: numberOrZero(input.rollingLimits.maxRowsPerDay)
  };
}

function numberOrZero(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
