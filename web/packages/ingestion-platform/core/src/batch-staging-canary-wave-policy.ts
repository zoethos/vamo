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
import { extractBatchDryRunReportMetrics } from "./batch-dry-run-report-metrics.js";
import { isVamoStagingTargetCategoryCompatible } from "./batch-staging-canary-wave-target-compat.js";
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
  | "no_eligible_items"
  | "unit_key_not_found"
  | "unit_not_dry_run_succeeded"
  | "unit_target_mismatch"
  | "unit_selection_exceeds_max_units"
  | "unit_category_unsupported";

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
    role: AdminPrincipal["role"] | "autonomous_agent";
    assuranceLevel: AdminPrincipal["assuranceLevel"] | "policy";
    policyApprovedBy?: string | null;
    policyApprovalAuditId?: string | null;
  };
  safetySummary: string[];
}

export interface BatchStagingCanaryWaveUnitSelectionIssue {
  unitKey: string;
  code: BatchStagingCanaryWaveBlockCode;
  message: string;
}

export type EvaluateBatchStagingCanaryWaveApprovalResult =
  | { ok: true; plan: BatchStagingCanaryWaveApprovalPlan }
  | { ok: false; blocks: BatchStagingCanaryWaveBlock[]; unitIssues?: BatchStagingCanaryWaveUnitSelectionIssue[] };

export interface EvaluateBatchStagingCanaryWaveApprovalInput {
  projectKey: string;
  snapshot: BatchQueueSnapshot;
  principal: AdminPrincipal;
  targetKey: string;
  targetEnvironment: string;
  maxUnits: number;
  maxRows: number;
  auditReason: string;
  unitKeys?: readonly string[];
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
        "Staging verification approval requires an ingestion_admin (role=admin) principal."
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
      message: "Staging verification approval requires verified MFA step-up (AAL2)."
    });
  }

  if (!hasFreshStepUp(input.principal, now)) {
    blocks.push({
      code: "fresh_step_up_required",
      message: "Staging verification approval requires a fresh MFA step-up."
    });
  }

  if (!auditReason) {
    blocks.push({
      code: "audit_reason_required",
      message: "A non-empty audit reason is required to approve staging verification."
    });
  }

  if (input.targetEnvironment === "production") {
    blocks.push({
      code: "production_environment_forbidden",
      message: "Production is forbidden for staging verification batches in IP-18.5."
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
      message: "Staging verification batches may only target explicit environment staging."
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
      message: "Staging verification approval may only run for simulation plans."
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
        "The first live staging verification batch is hard-capped at 1 unit. Run and verify a 1-unit batch before widening."
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

  const hintedUnitKeys = normalizeUnitKeyHints(input.unitKeys);
  if (hintedUnitKeys.length > 0) {
    return finalizeExplicitUnitSelection({
      input,
      hintedUnitKeys,
      candidates,
      auditReason,
      now
    });
  }

  const eligible: Array<{
    item: BatchQueueItem;
    report: BatchDryRunReport;
    expectedTargetWrites: number;
  }> = [];
  let firstSkipBlock: BatchStagingCanaryWaveBlock | undefined;

  for (const item of candidates) {
    const parsed = parseDryRunReport(item);
    if (!parsed.ok) {
      firstSkipBlock ??= parsed.block;
      continue;
    }
    if (parsed.expectedTargetWrites > STAGING_CANARY_MAX_ROWS) {
      firstSkipBlock ??= {
        code: "unit_row_bound_exceeded",
        message: `Unit "${item.unitKey}" exceeds the per-unit max target writes bound (${STAGING_CANARY_MAX_ROWS}).`
      };
      continue;
    }
    eligible.push({
      item,
      report: parsed.report,
      expectedTargetWrites: parsed.expectedTargetWrites
    });
  }

  const selected: typeof eligible = [];
  let totalPlannedRows = 0;

  for (const entry of eligible) {
    if (selected.length >= input.maxUnits) {
      break;
    }
    if (totalPlannedRows + entry.expectedTargetWrites > input.maxRows) {
      break;
    }
    selected.push(entry);
    totalPlannedRows += entry.expectedTargetWrites;
  }

  if (selected.length === 0) {
    blocks.push(
      firstSkipBlock ?? {
        code: "no_eligible_items",
        message:
          "There are no simulation-passed scopes with valid reports matching the requested bounds."
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
          message: `Selected units exceed the wave max target writes bound (${input.maxRows}).`
        }
      ]
    };
  }

  return buildApprovalPlan({
    input,
    selected,
    totalPlannedRows,
    auditReason,
    now
  });
}

export function countStagingCanaryWaveEligibleUnits(snapshot: BatchQueueSnapshot): number {
  return snapshot.items.filter((item) => isStagingCanaryWaveEligibleUnit(item).ok).length;
}

export function isStagingCanaryWaveEligibleUnit(
  item: BatchQueueItem
): { ok: true; expectedTargetWrites: number; sourceCandidates: number } | { ok: false; code: BatchStagingCanaryWaveBlockCode } {
  if (item.status !== "dry_run_succeeded") {
    return { ok: false, code: "unit_not_dry_run_succeeded" };
  }
  if (!isVamoStagingTargetCategoryCompatible(item.category)) {
    return { ok: false, code: "unit_category_unsupported" };
  }
  const parsed = parseDryRunReport(item);
  if (!parsed.ok) {
    return { ok: false, code: parsed.block.code };
  }
  if (parsed.expectedTargetWrites > STAGING_CANARY_MAX_ROWS) {
    return { ok: false, code: "unit_row_bound_exceeded" };
  }
  return {
    ok: true,
    expectedTargetWrites: parsed.expectedTargetWrites,
    sourceCandidates: parsed.sourceCandidates
  };
}

function finalizeExplicitUnitSelection(input: {
  input: EvaluateBatchStagingCanaryWaveApprovalInput;
  hintedUnitKeys: string[];
  candidates: BatchQueueItem[];
  auditReason: string;
  now: string;
}): EvaluateBatchStagingCanaryWaveApprovalResult {
  const candidateByKey = new Map(input.candidates.map((item) => [item.unitKey, item]));
  const unitIssues: BatchStagingCanaryWaveUnitSelectionIssue[] = [];
  const selected: Array<{
    item: BatchQueueItem;
    report: BatchDryRunReport;
    expectedTargetWrites: number;
  }> = [];

  for (const unitKey of input.hintedUnitKeys) {
    const item = input.input.snapshot.items.find((entry) => entry.unitKey === unitKey);
    if (!item) {
      unitIssues.push({
        unitKey,
        code: "unit_key_not_found",
        message: `Unit "${unitKey}" is not present in the active batch queue.`
      });
      continue;
    }
    if (item.status !== "dry_run_succeeded") {
      unitIssues.push({
        unitKey,
        code: "unit_not_dry_run_succeeded",
        message: `Unit "${unitKey}" must be simulation-passed; got ${item.status}.`
      });
      continue;
    }
    if (
      item.targetKey !== input.input.targetKey ||
      item.targetEnvironment !== input.input.targetEnvironment
    ) {
      unitIssues.push({
        unitKey,
        code: "unit_target_mismatch",
        message: `Unit "${unitKey}" target ${item.targetKey}/${item.targetEnvironment} does not match wave target ${input.input.targetKey}/${input.input.targetEnvironment}.`
      });
      continue;
    }
    if (!candidateByKey.has(unitKey)) {
      unitIssues.push({
        unitKey,
        code: "unit_not_dry_run_succeeded",
        message: `Unit "${unitKey}" is not an eligible simulation-passed scope for this staging verification.`
      });
      continue;
    }
    const parsed = parseDryRunReport(item);
    if (!parsed.ok) {
      unitIssues.push({
        unitKey,
        code: parsed.block.code,
        message: parsed.block.message
      });
      continue;
    }
    if (parsed.expectedTargetWrites > STAGING_CANARY_MAX_ROWS) {
      unitIssues.push({
        unitKey,
        code: "unit_row_bound_exceeded",
        message: `Unit "${unitKey}" exceeds the per-unit max target writes bound (${STAGING_CANARY_MAX_ROWS}).`
      });
      continue;
    }
    selected.push({ item, report: parsed.report, expectedTargetWrites: parsed.expectedTargetWrites });
  }

  if (unitIssues.length > 0) {
    return {
      ok: false,
      blocks: [
        {
          code: "no_eligible_items",
          message: "One or more selected scopes failed staging verification revalidation."
        }
      ],
      unitIssues
    };
  }

  if (selected.length === 0) {
    return {
      ok: false,
      blocks: [
        {
          code: "no_eligible_items",
          message: "No valid simulation-passed scopes were selected for staging verification approval."
        }
      ]
    };
  }

  if (selected.length > input.input.maxUnits) {
    return {
      ok: false,
      blocks: [
        {
          code: "unit_selection_exceeds_max_units",
          message: `Selected ${selected.length} unit(s) exceeds maxUnits (${input.input.maxUnits}).`
        }
      ]
    };
  }

  const totalPlannedRows = selected.reduce((sum, entry) => sum + entry.expectedTargetWrites, 0);
  if (totalPlannedRows > input.input.maxRows) {
    return {
      ok: false,
      blocks: [
        {
          code: "wave_row_bound_exceeded",
          message: `Selected units exceed the wave max target writes bound (${input.input.maxRows}).`
        }
      ]
    };
  }

  selected.sort((a, b) => a.item.runOrder - b.item.runOrder);
  return buildApprovalPlan({
    input: input.input,
    selected,
    totalPlannedRows,
    auditReason: input.auditReason,
    now: input.now
  });
}

function buildApprovalPlan(input: {
  input: EvaluateBatchStagingCanaryWaveApprovalInput;
  selected: Array<{
    item: BatchQueueItem;
    report: BatchDryRunReport;
    expectedTargetWrites: number;
  }>;
  totalPlannedRows: number;
  auditReason: string;
  now: string;
}): EvaluateBatchStagingCanaryWaveApprovalResult {
  const unitKeys = input.selected.map((entry) => entry.item.unitKey);
  const waveKey =
    input.input.waveKey?.trim() ||
    buildWaveKey(input.input.snapshot.planId, unitKeys, input.auditReason);
  const approvedAt = input.now;
  const approvalExpiresAt = new Date(
    Date.parse(approvedAt) + STAGING_CANARY_APPROVAL_MAX_AGE_MS
  ).toISOString();

  return {
    ok: true,
    plan: {
      action: "approve_batch_staging_canary_wave",
      waveKey,
      projectKey: input.input.projectKey,
      queueId: input.input.snapshot.queueId,
      planId: input.input.snapshot.planId,
      targetKey: input.input.targetKey,
      targetEnvironment: "staging",
      maxUnits: input.input.maxUnits,
      maxRows: input.input.maxRows,
      unitKeys,
      selectedUnits: input.selected.map((entry) => entry.item),
      totalPlannedRows: input.totalPlannedRows,
      auditReason: input.auditReason,
      approvedAt,
      approvalExpiresAt,
      approvedBy: {
        email: input.input.principal.email,
        role: input.input.principal.role,
        assuranceLevel: input.input.principal.assuranceLevel
      },
      safetySummary: [...DEFAULT_SAFETY_SUMMARY]
    }
  };
}

function normalizeUnitKeyHints(unitKeys: readonly string[] | undefined): string[] {
  if (!unitKeys || unitKeys.length === 0) {
    return [];
  }
  const seen = new Set<string>();
  const normalized: string[] = [];
  for (const unitKey of unitKeys) {
    const trimmed = unitKey.trim();
    if (!trimmed || seen.has(trimmed)) {
      continue;
    }
    seen.add(trimmed);
    normalized.push(trimmed);
  }
  return normalized;
}

function parseDryRunReport(
  item: BatchQueueItem
):
  | { ok: true; report: BatchDryRunReport; expectedTargetWrites: number; sourceCandidates: number }
  | { ok: false; block: BatchStagingCanaryWaveBlock } {
  const report = item.dryRunReport;
  if (!report) {
    return {
      ok: false,
      block: {
        code: "dry_run_report_missing",
        message: `Unit "${item.unitKey}" passed simulation but has no simulation report.`
      }
    };
  }
  if (report.wroteToTarget !== false) {
    return {
      ok: false,
      block: {
        code: "dry_run_invariant_violated",
        message: `Unit "${item.unitKey}" simulation report violates wroteToTarget=false.`
      }
    };
  }
  if (!isVamoStagingTargetCategoryCompatible(item.category)) {
    return {
      ok: false,
      block: {
        code: "unit_category_unsupported",
        message: `Unit "${item.unitKey}" category ${item.category} cannot be mapped to a supported Vamo feature type.`
      }
    };
  }
  const metrics = extractBatchDryRunReportMetrics(report);
  if (!metrics) {
    return {
      ok: false,
      block: {
        code: "dry_run_invariant_violated",
        message: `Unit "${item.unitKey}" simulation report is missing source/target write metrics.`
      }
    };
  }
  return {
    ok: true,
    report,
    expectedTargetWrites: metrics.expectedTargetWrites,
    sourceCandidates: metrics.sourceCandidates
  };
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
