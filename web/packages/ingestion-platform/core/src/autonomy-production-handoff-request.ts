/**
 * Parse production package autonomy handoff requests.
 */

import {
  PRODUCTION_HANDOFF_DISABLE_STATE,
  PRODUCTION_HANDOFF_ENABLE_STATE,
  type AutonomyProductionHandoffState
} from "./autonomy-production-handoff-policy.js";

export interface AutonomyProductionHandoffRequest {
  projectKey: string;
  policyKey: string;
  expectedEnabled: boolean;
  requestedEnabled: boolean;
  auditReason: string;
  confirmedState: AutonomyProductionHandoffState;
}

export function parseAutonomyProductionHandoffRequest(
  body: unknown
):
  | { ok: true; request: AutonomyProductionHandoffRequest }
  | { ok: false; error: string; code?: string } {
  if (!body || typeof body !== "object") {
    return { ok: false, error: "Request body must be a JSON object.", code: "invalid_body" };
  }

  const value = body as Record<string, unknown>;
  const projectKey = readString(value.projectKey);
  const policyKey = readString(value.policyKey);
  const expectedEnabled = readBoolean(value.expectedEnabled);
  const requestedEnabled = readBoolean(value.requestedEnabled);
  const auditReason = readString(value.auditReason);
  const confirmedState = readHandoffState(value.confirmedState);

  if (!projectKey) {
    return { ok: false, error: "projectKey is required.", code: "project_key_required" };
  }
  if (!policyKey) {
    return { ok: false, error: "policyKey is required.", code: "policy_key_required" };
  }
  if (expectedEnabled === null) {
    return { ok: false, error: "expectedEnabled is required.", code: "expected_enabled_required" };
  }
  if (requestedEnabled === null) {
    return { ok: false, error: "requestedEnabled is required.", code: "requested_enabled_required" };
  }
  if (!auditReason) {
    return { ok: false, error: "auditReason is required.", code: "audit_reason_required" };
  }
  if (!confirmedState) {
    return { ok: false, error: "confirmedState is required.", code: "confirmed_state_required" };
  }

  const expectedConfirmedState = requestedEnabled
    ? PRODUCTION_HANDOFF_ENABLE_STATE
    : PRODUCTION_HANDOFF_DISABLE_STATE;
  if (confirmedState !== expectedConfirmedState) {
    return {
      ok: false,
      error: "confirmedState must match requestedEnabled.",
      code: "confirmed_state_mismatch"
    };
  }

  return {
    ok: true,
    request: {
      projectKey,
      policyKey,
      expectedEnabled,
      requestedEnabled,
      auditReason,
      confirmedState
    }
  };
}

function readString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function readBoolean(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function readHandoffState(value: unknown): AutonomyProductionHandoffState | null {
  const state = readString(value);
  if (state === PRODUCTION_HANDOFF_ENABLE_STATE || state === PRODUCTION_HANDOFF_DISABLE_STATE) {
    return state;
  }
  return null;
}
