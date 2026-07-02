/**
 * Pure batch staging-canary wave approval policy (IP-18.5.1).
 *
 * Selects bounded eligible `dry_run_succeeded` queue units and validates the
 * operator approval gate. No DB, network, provider, or consumer target access.
 *
 * Approval requires ingestion_admin (role=admin) + verified AAL2 + fresh MFA
 * step-up + non-empty audit reason, mirroring IP-16 staging-canary semantics.
 */

import {
  ADMIN_FRESH_STEP_UP_CLOCK_SKEW_MS,
  type AdminPrincipal
} from "./admin-auth.js";
import type { BatchDryRunReport, BatchQueueItem, BatchQueueSnapshot } from "./batch-queue-read-model.js";
import {
  STAGING_CANARY_APPROVAL_MAX_AGE_MS,
  STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS,
  STAGING_CANARY_MAX_ROWS
} from "./staging-canary-policy.js";

export type BatchStagingCanaryWaveBlockCode =
  | "role_denied"
  | "scope_denied"
  | "mfa_required"
  | "fresh_step_up_required"
  | "audit_reason_required"
  | "production_environment_forbidden"
  | "target_environment_required"
  | "target_environment_mismatch"
  | "target_key_mismatch"
  | "max_units_invalid"
  | "max_rows_invalid"
  | "ramp_exceeded"
  | "unsafe_safety_mode"
  | "dry_run_report_missing"
  | "dry_run_invariant_violated"
  | "unit_row_bound_exceeded"
  | "wave_row_bound_exceeded"
  | "no_eligible_items";

export interface BatchStagingCanaryWaveBlock {
  code: BatchStagingCanaryWaveBlockCode;
  message: string;
}

export interface BatchStagingCanaryWaveApprovalPlan {
  action: "approve_batch_staging_canary_wave";
  waveKey: string;
  projectKey: string;
  queueId: string;
  planId: string;
  targetKey: string;
  targetEnvironment: "staging";
  maxUnits: number;
  maxRows: number;
  unitKeys: string[];
  selectedUnits: BatchQueueItem[];
  totalPlannedRows: number;
  auditReason: string;
  approvedAt: string;
  approvalExpiresAt: string;
  approvedBy: {
    email: string;
    role: AdminPrincipal["role"];
    assuranceLevel: AdminPrincipal["assuranceLevel"];
  };
  safetySummary: string[];
}

export type EvaluateBatchStagingCanaryWaveApprovalResult =
  | { ok: true; plan: BatchStagingCanaryWaveApprovalPlan }
  | { ok: false; blocks: BatchStagingCanaryWaveBlock[] };

export interface EvaluateBatchStagingCanaryWaveApprovalInput {
  projectKey: string;
  snapshot: BatchQueueSnapshot;
  principal: AdminPrincipal;
  targetKey: string;
  targetEnvironment: string;
  maxUnits: number;
  maxRows: number;
  auditReason: string;
  waveKey?: string;
  now?: string;
}

const DEFAULT_SAFETY_SUMMARY = [
  "Control-plane wave approval only.",
  "No Vamo staging writes in this action.",
  "No Vamo production writes.",
  "Live staging execution requires a separate confirmation-gated runbook step."
] as const;

const FIRST_WAVE_MAX_UNITS = 1;

export function evaluateBatchStagingCanaryWaveApproval(
  input: EvaluateBatchStagingCanaryWaveApprovalInput
): EvaluateBatchStagingCanaryWaveApprovalResult {
  const blocks: BatchStagingCanaryWaveBlock[] = [];
  const auditReason = input.auditReason.trim();
  const now = input.now ?? new Date().toISOString();

  if (input.principal.role !== "admin") {
    blocks.push({
      code: "role_denied",
      message:
        "Batch staging-canary wave approval requires an ingestion_admin (role=admin) principal."
    });
  }

  if (!principalHasProjectScope(input.principal, input.projectKey)) {
    blocks.push({
      code: "scope_denied",
      message: "The operator is not scoped to this ingestion project."
    });
  }

  if (
    input.principal.assuranceLevel !== "aal2" ||
    (input.principal.mfaRequired && !input.principal.hasVerifiedMfaFactor)
  ) {
    blocks.push({
      code: "mfa_required",
      message: "Batch staging-canary wave approval requires verified MFA step-up (AAL2)."
    });
  }

  if (!hasFreshStepUp(input.principal, now)) {
    blocks.push({
      code: "fresh_step_up_required",
      message: "Batch staging-canary wave approval requires a fresh MFA step-up."
    });
  }

  if (!auditReason) {
    blocks.push({
      code: "audit_reason_required",
      message: "A non-empty audit reason is required to approve a staging-canary wave."
    });
  }

  if (input.targetEnvironment === "production") {
    blocks.push({
      code: "production_environment_forbidden",
      message: "Production is forbidden for batch staging-canary waves in IP-18.5."
    });
  }

  if (!input.targetEnvironment) {
    blocks.push({
      code: "target_environment_required",
      message: "Wave approval requires an explicit target environment."
    });
  } else if (input.targetEnvironment !== "staging") {
    blocks.push({
      code: "target_environment_mismatch",
      message: "Batch staging-canary waves may only target explicit environment staging."
    });
  }

  if (input.snapshot.targetKey !== input.targetKey) {
    blocks.push({
      code: "target_key_mismatch",
      message: "Wave target key must match the active batch plan target key."
    });
  }

  if (input.snapshot.targetEnvironment !== input.targetEnvironment) {
    blocks.push({
      code: "target_environment_mismatch",
      message: "Wave target environment must match the active batch plan."
    });
  }

  if (input.snapshot.safetyMode !== "dry_run") {
    blocks.push({
      code: "unsafe_safety_mode",
      message: "Batch staging-canary wave approval may only run for dry_run plans."
    });
  }

  if (!Number.isFinite(input.maxUnits) || input.maxUnits < 1) {
    blocks.push({
      code: "max_units_invalid",
      message: "maxUnits must be a positive integer."
    });
  }

  if (!Number.isFinite(input.maxRows) || input.maxRows < 1) {
    blocks.push({
      code: "max_rows_invalid",
      message: "maxRows must be a positive integer."
    });
  }

  const hasPriorStagingCanarySuccess = input.snapshot.items.some(
    (item) =>
      item.targetKey === input.targetKey &&
      item.targetEnvironment === input.targetEnvironment &&
      item.status === "staging_canary_succeeded"
  );
  if (!hasPriorStagingCanarySuccess && input.maxUnits > FIRST_WAVE_MAX_UNITS) {
    blocks.push({
      code: "ramp_exceeded",
      message:
        "The first live staging-canary wave is hard-capped at 1 unit. Run and verify a 1-unit wave before widening."
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const candidates = input.snapshot.items
    .filter((item) => item.status === "dry_run_succeeded")
    .filter((item) => item.targetKey === input.targetKey)
    .filter((item) => item.targetEnvironment === input.targetEnvironment)
    .sort((a, b) => a.runOrder - b.runOrder);

  const eligible: Array<{ item: BatchQueueItem; report: BatchDryRunReport; writeCount: number }> = [];
  let firstSkipBlock: BatchStagingCanaryWaveBlock | undefined;

  for (const item of candidates) {
    const parsed = parseDryRunReport(item);
    if (!parsed.ok) {
      firstSkipBlock ??= parsed.block;
      continue;
    }
    if (parsed.writeCount > STAGING_CANARY_MAX_ROWS) {
      firstSkipBlock ??= {
        code: "unit_row_bound_exceeded",
        message: `Unit "${item.unitKey}" exceeds STAGING_CANARY_MAX_ROWS (${STAGING_CANARY_MAX_ROWS}).`
      };
      continue;
    }
    eligible.push({ item, report: parsed.report, writeCount: parsed.writeCount });
  }

  const selected: typeof eligible = [];
  let totalPlannedRows = 0;

  for (const entry of eligible) {
    if (selected.length >= input.maxUnits) {
      break;
    }
    if (totalPlannedRows + entry.writeCount > input.maxRows) {
      break;
    }
    selected.push(entry);
    totalPlannedRows += entry.writeCount;
  }

  if (selected.length === 0) {
    blocks.push(
      firstSkipBlock ?? {
        code: "no_eligible_items",
        message:
          "There are no dry_run_succeeded units with valid dry-run reports matching the requested bounds."
      }
    );
    return { ok: false, blocks };
  }

  if (totalPlannedRows > input.maxRows) {
    return {
      ok: false,
      blocks: [
        {
          code: "wave_row_bound_exceeded",
          message: `Selected units exceed the wave maxRows bound (${input.maxRows}).`
        }
      ]
    };
  }

  const unitKeys = selected.map((entry) => entry.item.unitKey);
  const waveKey =
    input.waveKey?.trim() ||
    buildWaveKey(input.snapshot.planId, unitKeys, auditReason);

  const approvedAt = now;
  const approvalExpiresAt = new Date(
    Date.parse(approvedAt) + STAGING_CANARY_APPROVAL_MAX_AGE_MS
  ).toISOString();

  return {
    ok: true,
    plan: {
      action: "approve_batch_staging_canary_wave",
      waveKey,
      projectKey: input.projectKey,
      queueId: input.snapshot.queueId,
      planId: input.snapshot.planId,
      targetKey: input.targetKey,
      targetEnvironment: "staging",
      maxUnits: input.maxUnits,
      maxRows: input.maxRows,
      unitKeys,
      selectedUnits: selected.map((entry) => entry.item),
      totalPlannedRows,
      auditReason,
      approvedAt,
      approvalExpiresAt,
      approvedBy: {
        email: input.principal.email,
        role: input.principal.role,
        assuranceLevel: input.principal.assuranceLevel
      },
      safetySummary: [...DEFAULT_SAFETY_SUMMARY]
    }
  };
}

export function countStagingCanaryWaveEligibleUnits(snapshot: BatchQueueSnapshot): number {
  return snapshot.items.filter((item) => {
    if (item.status !== "dry_run_succeeded") {
      return false;
    }
    const parsed = parseDryRunReport(item);
    return parsed.ok && parsed.writeCount <= STAGING_CANARY_MAX_ROWS;
  }).length;
}

function parseDryRunReport(
  item: BatchQueueItem
):
  | { ok: true; report: BatchDryRunReport; writeCount: number }
  | { ok: false; block: BatchStagingCanaryWaveBlock } {
  const report = item.dryRunReport;
  if (!report) {
    return {
      ok: false,
      block: {
        code: "dry_run_report_missing",
        message: `Unit "${item.unitKey}" is dry_run_succeeded but has no dry-run report.`
      }
    };
  }
  if (report.wroteToTarget !== false) {
    return {
      ok: false,
      block: {
        code: "dry_run_invariant_violated",
        message: `Unit "${item.unitKey}" dry-run report violates wroteToTarget=false.`
      }
    };
  }
  const writeCount = report.insertCount + report.updateCount;
  return { ok: true, report, writeCount };
}

function buildWaveKey(planId: string, unitKeys: string[], auditReason: string): string {
  const digest = auditReason.length > 0 ? auditReason.slice(0, 24).replace(/\s+/g, "-") : "none";
  return `batch-staging-canary:${planId}:${unitKeys.length}:${unitKeys[0] ?? "none"}:${digest}`;
}

function principalHasProjectScope(principal: AdminPrincipal, projectKey: string): boolean {
  return principal.scopes.includes("*") || principal.scopes.includes(projectKey);
}

function hasFreshStepUp(principal: AdminPrincipal, now: string): boolean {
  const satisfiedAt = principal.stepUpSatisfiedAt;
  if (!satisfiedAt) {
    return false;
  }
  const nowMs = Date.parse(now);
  const satisfiedMs = Date.parse(satisfiedAt);
  if (!Number.isFinite(nowMs) || !Number.isFinite(satisfiedMs)) {
    return false;
  }
  const ageMs = nowMs - satisfiedMs;
  return ageMs >= -ADMIN_FRESH_STEP_UP_CLOCK_SKEW_MS && ageMs <= STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS;
}
