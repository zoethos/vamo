/**
 * Parse autonomy ramp promotion/demotion requests (IP-18.7.4 PR2).
 */

import { isAutonomyRampMode, type AutonomyRampMode } from "./autonomy-ramp-policy.js";

export interface AutonomyRampPromoteRequest {
  projectKey: string;
  policyKey: string;
  expectedCurrentMode: AutonomyRampMode;
  requestedMode: AutonomyRampMode;
  auditReason: string;
  confirmedMode: string;
  acknowledgedWarnings?: boolean;
}

export function parseAutonomyRampPromoteRequest(
  body: unknown
):
  | { ok: true; request: AutonomyRampPromoteRequest }
  | { ok: false; error: string; code?: string } {
  if (!body || typeof body !== "object") {
    return { ok: false, error: "Request body must be a JSON object.", code: "invalid_body" };
  }

  const value = body as Record<string, unknown>;
  const projectKey = readString(value.projectKey);
  const policyKey = readString(value.policyKey);
  const expectedCurrentMode = readRampMode(value.expectedCurrentMode);
  const requestedMode = readRampMode(value.requestedMode);
  const auditReason = readString(value.auditReason);
  const confirmedMode = readString(value.confirmedMode);

  if (!projectKey) {
    return { ok: false, error: "projectKey is required.", code: "project_key_required" };
  }
  if (!policyKey) {
    return { ok: false, error: "policyKey is required.", code: "policy_key_required" };
  }
  if (!expectedCurrentMode) {
    return { ok: false, error: "expectedCurrentMode is required.", code: "expected_mode_required" };
  }
  if (!requestedMode) {
    return { ok: false, error: "requestedMode is required.", code: "requested_mode_required" };
  }
  if (!auditReason) {
    return { ok: false, error: "auditReason is required.", code: "audit_reason_required" };
  }
  if (!confirmedMode) {
    return { ok: false, error: "confirmedMode is required.", code: "confirmed_mode_required" };
  }
  if (confirmedMode !== requestedMode) {
    return {
      ok: false,
      error: "confirmedMode must exactly match requestedMode.",
      code: "confirmed_mode_mismatch"
    };
  }

  return {
    ok: true,
    request: {
      projectKey,
      policyKey,
      expectedCurrentMode,
      requestedMode,
      auditReason,
      confirmedMode,
      acknowledgedWarnings: value.acknowledgedWarnings === true
    }
  };
}

function readString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function readRampMode(value: unknown): AutonomyRampMode | null {
  const trimmed = readString(value);
  return isAutonomyRampMode(trimmed) ? trimmed : null;
}
