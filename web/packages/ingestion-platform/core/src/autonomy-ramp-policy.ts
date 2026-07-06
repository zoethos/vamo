/**
 * Autonomy ramp policy (IP-18.7.2).
 *
 * Names the operating mode for an autonomy policy so "2 units/day" is explicit
 * bootstrap commissioning, not the steady-state ingestion model.
 */

import type { CommandActorType } from "./commands.js";
import type { AutonomyPolicyEnvelope } from "./autonomy-policy.js";

export const AUTONOMY_RAMP_MODES = [
  "bootstrap",
  "staging_ramp",
  "volume_ramp",
  "steady_state"
] as const;

export type AutonomyRampMode = typeof AUTONOMY_RAMP_MODES[number];

export interface AutonomyRampProfile {
  mode: AutonomyRampMode;
  label: string;
  description: string;
  maxUnitsPerCycle: number;
  maxRowsPerCycle: number;
  rollingLimits: {
    maxCyclesPerDay: number;
    maxUnitsPerDay: number;
    maxRowsPerDay: number;
  };
  guardThresholds: {
    maxBlockerRate: number;
    maxDiffDriftRate: number;
    maxConsumerApplyRejectRate: number;
    pauseOnNewBlockerCode: boolean;
  };
  productionInboxEnabled: boolean;
  recommendedNextMode?: AutonomyRampMode;
}

export interface AutonomyRampResolution {
  mode: AutonomyRampMode;
  label: string;
  description: string;
  profile: AutonomyRampProfile;
  recommendedNextMode?: AutonomyRampMode;
  policyWithinProfile: boolean;
  warnings: string[];
}

export type AutonomyRampPromotionBlockCode =
  | "same_mode"
  | "unknown_mode"
  | "skips_required_ramp"
  | "missing_audit_reason"
  | "actor_not_operator"
  | "production_handoff_not_ready";

export interface EvaluateAutonomyRampPromotionInput {
  currentMode: AutonomyRampMode;
  requestedMode: AutonomyRampMode;
  actor: {
    type: CommandActorType;
    id: string;
    role?: "viewer" | "operator" | "admin";
  };
  auditReason: string;
  productionInboxSupported?: boolean;
}

export type EvaluateAutonomyRampPromotionResult =
  | {
      ok: true;
      fromMode: AutonomyRampMode;
      toMode: AutonomyRampMode;
      profile: AutonomyRampProfile;
      auditReason: string;
    }
  | {
      ok: false;
      blocks: Array<{
        code: AutonomyRampPromotionBlockCode;
        message: string;
      }>;
    };

export const AUTONOMY_RAMP_PROFILES: Record<AutonomyRampMode, AutonomyRampProfile> = {
  bootstrap: {
    mode: "bootstrap",
    label: "Bootstrap proof",
    description: "Tiny commissioning limits used to prove the agent, telemetry, and fail-closed behavior.",
    maxUnitsPerCycle: 1,
    maxRowsPerCycle: 2,
    rollingLimits: {
      maxCyclesPerDay: 4,
      maxUnitsPerDay: 2,
      maxRowsPerDay: 4
    },
    guardThresholds: {
      maxBlockerRate: 0.1,
      maxDiffDriftRate: 0,
      maxConsumerApplyRejectRate: 0,
      pauseOnNewBlockerCode: true
    },
    productionInboxEnabled: false,
    recommendedNextMode: "staging_ramp"
  },
  staging_ramp: {
    mode: "staging_ramp",
    label: "Staging ramp",
    description: "Controlled staging expansion after bootstrap proof; still no production inbox autonomy.",
    maxUnitsPerCycle: 5,
    maxRowsPerCycle: 100,
    rollingLimits: {
      maxCyclesPerDay: 20,
      maxUnitsPerDay: 25,
      maxRowsPerDay: 500
    },
    guardThresholds: {
      maxBlockerRate: 0.05,
      maxDiffDriftRate: 0.01,
      maxConsumerApplyRejectRate: 0,
      pauseOnNewBlockerCode: true
    },
    productionInboxEnabled: false,
    recommendedNextMode: "volume_ramp"
  },
  volume_ramp: {
    mode: "volume_ramp",
    label: "Volume ramp",
    description: "Higher-volume staging/prod-prep mode governed by telemetry thresholds and package-wave readiness.",
    maxUnitsPerCycle: 25,
    maxRowsPerCycle: 5_000,
    rollingLimits: {
      maxCyclesPerDay: 100,
      maxUnitsPerDay: 250,
      maxRowsPerDay: 100_000
    },
    guardThresholds: {
      maxBlockerRate: 0.03,
      maxDiffDriftRate: 0.005,
      maxConsumerApplyRejectRate: 0.001,
      pauseOnNewBlockerCode: true
    },
    productionInboxEnabled: false,
    recommendedNextMode: "steady_state"
  },
  steady_state: {
    mode: "steady_state",
    label: "Steady state",
    description: "Autonomous production-scale operation after package waves, apply telemetry, and quotas are proven.",
    maxUnitsPerCycle: 100,
    maxRowsPerCycle: 25_000,
    rollingLimits: {
      maxCyclesPerDay: 250,
      maxUnitsPerDay: 1_000,
      maxRowsPerDay: 1_000_000
    },
    guardThresholds: {
      maxBlockerRate: 0.02,
      maxDiffDriftRate: 0.002,
      maxConsumerApplyRejectRate: 0.001,
      pauseOnNewBlockerCode: true
    },
    productionInboxEnabled: true
  }
};

const NEXT_MODE: Partial<Record<AutonomyRampMode, AutonomyRampMode>> = {
  bootstrap: "staging_ramp",
  staging_ramp: "volume_ramp",
  volume_ramp: "steady_state"
};

export function isAutonomyRampMode(value: unknown): value is AutonomyRampMode {
  return typeof value === "string" && AUTONOMY_RAMP_MODES.includes(value as AutonomyRampMode);
}

export function readAutonomyRampMode(summary: Record<string, unknown> | undefined): AutonomyRampMode {
  const directMode = summary?.rampMode;
  if (isAutonomyRampMode(directMode)) return directMode;
  const ramp = summary?.ramp;
  if (typeof ramp === "object" && ramp !== null && "mode" in ramp && isAutonomyRampMode(ramp.mode)) {
    return ramp.mode;
  }
  return "bootstrap";
}

export function resolveAutonomyRamp(policy: AutonomyPolicyEnvelope): AutonomyRampResolution {
  const mode = policy.rampMode ?? readAutonomyRampMode(policy.summary);
  const profile = AUTONOMY_RAMP_PROFILES[mode];
  const warnings: string[] = [];

  if (policy.maxUnitsPerCycle > profile.maxUnitsPerCycle) {
    warnings.push(
      `max_units_per_cycle ${policy.maxUnitsPerCycle} exceeds ${profile.mode} profile cap ${profile.maxUnitsPerCycle}`
    );
  }
  if (policy.maxRowsPerCycle > profile.maxRowsPerCycle) {
    warnings.push(
      `max_rows_per_cycle ${policy.maxRowsPerCycle} exceeds ${profile.mode} profile cap ${profile.maxRowsPerCycle}`
    );
  }

  const rollingWarnings = compareRollingLimits(policy.rollingLimits, profile);
  warnings.push(...rollingWarnings);

  if (
    profile.productionInboxEnabled === false &&
    policy.allowedTransitions.includes("deliver_production_inbox")
  ) {
    warnings.push(`${profile.mode} does not allow autonomous production inbox delivery`);
  }

  return {
    mode,
    label: profile.label,
    description: profile.description,
    profile,
    recommendedNextMode: profile.recommendedNextMode,
    policyWithinProfile: warnings.length === 0,
    warnings
  };
}

export function evaluateAutonomyRampPromotion(
  input: EvaluateAutonomyRampPromotionInput
): EvaluateAutonomyRampPromotionResult {
  const blocks: Array<{
    code: AutonomyRampPromotionBlockCode;
    message: string;
  }> = [];

  if (!isAutonomyRampMode(input.currentMode) || !isAutonomyRampMode(input.requestedMode)) {
    blocks.push({
      code: "unknown_mode",
      message: "Ramp promotion requires known autonomy ramp modes."
    });
  }

  if (input.currentMode === input.requestedMode) {
    blocks.push({
      code: "same_mode",
      message: "Requested ramp mode is already active."
    });
  }

  const expectedNext = NEXT_MODE[input.currentMode];
  if (expectedNext && input.requestedMode !== expectedNext) {
    blocks.push({
      code: "skips_required_ramp",
      message: `Ramp promotion must move from ${input.currentMode} to ${expectedNext} before ${input.requestedMode}.`
    });
  }

  if (!expectedNext && input.currentMode !== input.requestedMode) {
    blocks.push({
      code: "skips_required_ramp",
      message: `${input.currentMode} is the terminal ramp mode.`
    });
  }

  if (input.auditReason.trim().length === 0) {
    blocks.push({
      code: "missing_audit_reason",
      message: "Ramp promotion requires an audit reason."
    });
  }

  if (input.actor.type !== "operator" || input.actor.role !== "admin") {
    blocks.push({
      code: "actor_not_operator",
      message: "Ramp promotion requires an admin operator; autonomous agents cannot widen their own policy."
    });
  }

  if (input.requestedMode === "steady_state" && input.productionInboxSupported !== true) {
    blocks.push({
      code: "production_handoff_not_ready",
      message: "Steady-state autonomy requires production inbox package waves and apply telemetry."
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  return {
    ok: true,
    fromMode: input.currentMode,
    toMode: input.requestedMode,
    profile: AUTONOMY_RAMP_PROFILES[input.requestedMode],
    auditReason: input.auditReason.trim()
  };
}

function compareRollingLimits(
  rollingLimits: Record<string, unknown>,
  profile: AutonomyRampProfile
): string[] {
  const warnings: string[] = [];
  for (const key of ["maxCyclesPerDay", "maxUnitsPerDay", "maxRowsPerDay"] as const) {
    const value = rollingLimits[key];
    if (
      typeof value === "number" &&
      Number.isFinite(value) &&
      value > profile.rollingLimits[key]
    ) {
      warnings.push(`${key} ${value} exceeds ${profile.mode} profile cap ${profile.rollingLimits[key]}`);
    }
  }
  return warnings;
}
