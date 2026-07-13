/**
 * Pure policy and presenter helpers for production package autonomy handoff.
 *
 * This is deliberately narrower than a generic policy editor: operators can
 * enable or disable autonomous production package approval/delivery, while
 * consumer apply remains disabled unless a future policy explicitly adds it.
 */

import type { AdminAssuranceLevel, AdminRole } from "./admin-auth.js";
import type { CommandActorType } from "./commands.js";
import type { AutonomyPolicyEnvelope } from "./autonomy-policy.js";

export const PRODUCTION_HANDOFF_ENABLE_STATE = "enabled" as const;
export const PRODUCTION_HANDOFF_DISABLE_STATE = "disabled" as const;
export type AutonomyProductionHandoffState =
  | typeof PRODUCTION_HANDOFF_ENABLE_STATE
  | typeof PRODUCTION_HANDOFF_DISABLE_STATE;

export type AutonomyProductionHandoffBlockCode =
  | "same_state"
  | "missing_audit_reason"
  | "missing_actor_identity"
  | "actor_not_admin"
  | "fresh_step_up_required";

export interface EvaluateAutonomyProductionHandoffChangeInput {
  currentEnabled: boolean;
  requestedEnabled: boolean;
  actor: {
    type: CommandActorType;
    id: string;
    role?: AdminRole;
    assuranceLevel?: AdminAssuranceLevel;
    stepUpFresh?: boolean;
  };
  auditReason: string;
}

export type EvaluateAutonomyProductionHandoffChangeResult =
  | {
      ok: true;
      direction: "enable" | "disable";
      fromEnabled: boolean;
      toEnabled: boolean;
      auditReason: string;
    }
  | {
      ok: false;
      blocks: Array<{
        code: AutonomyProductionHandoffBlockCode;
        message: string;
      }>;
    };

export interface AutonomyProductionHandoffCardPresentation {
  enabled: boolean;
  state: AutonomyProductionHandoffState;
  stateLabel: string;
  tone: "good" | "watch";
  requestedState: AutonomyProductionHandoffState;
  requestedStateLabel: string;
  description: string;
  allowedActions: string[];
  deniedActions: string[];
  safeguards: string[];
  rawPolicy: Record<string, unknown>;
}

export function isProductionHandoffEnabled(policy: AutonomyPolicyEnvelope): boolean {
  const handoff = policy.productionInboxHandoffPolicy ?? {};
  if (handoff.requiresIp18_6 === true || handoff.requiresIp18_6 === "true") {
    return false;
  }
  return handoff.enabled === true;
}

export function presentAutonomyProductionHandoffCard(
  policy: AutonomyPolicyEnvelope
): AutonomyProductionHandoffCardPresentation {
  const enabled = isProductionHandoffEnabled(policy);
  return {
    enabled,
    state: enabled ? PRODUCTION_HANDOFF_ENABLE_STATE : PRODUCTION_HANDOFF_DISABLE_STATE,
    stateLabel: enabled ? "Enabled" : "Disabled",
    tone: enabled ? "good" : "watch",
    requestedState: enabled ? PRODUCTION_HANDOFF_DISABLE_STATE : PRODUCTION_HANDOFF_ENABLE_STATE,
    requestedStateLabel: enabled ? "Disable production handoff" : "Enable production handoff",
    description: enabled
      ? "The agent may approve and deliver production inbox packages inside the active policy bounds."
      : "The agent pauses before production package approval or delivery until an admin enables this control.",
    allowedActions: [
      "Approve production package waves inside the active policy bounds.",
      "Deliver approved production packages to the Vamo inbox when production delivery credentials are present."
    ],
    deniedActions: [
      "Apply delivered packages to Vamo product tables.",
      "Bypass package checksums, delivery credentials, or telemetry gates.",
      "Widen ramp, daily limits, or package batch size."
    ],
    safeguards: [
      "Admin role is required.",
      "Enabling requires fresh MFA step-up and an audit reason.",
      "Every change writes an audit row and a policy event.",
      "Disabling narrows autonomy immediately and does not require fresh MFA."
    ],
    rawPolicy: policy.productionInboxHandoffPolicy ?? {}
  };
}

export function evaluateAutonomyProductionHandoffChange(
  input: EvaluateAutonomyProductionHandoffChangeInput
): EvaluateAutonomyProductionHandoffChangeResult {
  const blocks: Array<{
    code: AutonomyProductionHandoffBlockCode;
    message: string;
  }> = [];

  if (input.currentEnabled === input.requestedEnabled) {
    blocks.push({
      code: "same_state",
      message: "Production handoff is already in the requested state."
    });
  }

  if (input.auditReason.trim().length === 0) {
    blocks.push({
      code: "missing_audit_reason",
      message: "Production handoff changes require an audit reason."
    });
  }

  if (!input.actor.id.trim()) {
    blocks.push({
      code: "missing_actor_identity",
      message: "Production handoff changes require a named operator actor."
    });
  }

  if (input.actor.type !== "operator" || input.actor.role !== "admin") {
    blocks.push({
      code: "actor_not_admin",
      message: "Production handoff changes require an admin operator."
    });
  }

  if (
    input.requestedEnabled &&
    (input.actor.assuranceLevel !== "aal2" || input.actor.stepUpFresh !== true)
  ) {
    blocks.push({
      code: "fresh_step_up_required",
      message: "Enabling production package autonomy requires a fresh AAL2 operator step-up."
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  return {
    ok: true,
    direction: input.requestedEnabled ? "enable" : "disable",
    fromEnabled: input.currentEnabled,
    toEnabled: input.requestedEnabled,
    auditReason: input.auditReason.trim()
  };
}

export function productionHandoffStateLabel(enabled: boolean): AutonomyProductionHandoffState {
  return enabled ? PRODUCTION_HANDOFF_ENABLE_STATE : PRODUCTION_HANDOFF_DISABLE_STATE;
}
