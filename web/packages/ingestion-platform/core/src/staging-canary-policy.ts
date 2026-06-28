/**
 * Staging-canary approval policy (IP-16) — pure, deterministic, DB-free.
 *
 * Evaluates whether a reviewed dry run may be promoted
 * `review_required -> staging_write` and, if so, returns a bounded
 * `StagingCanaryPlan` (the shipment intent). It performs no I/O and imports no
 * node/pg/fs, so it is browser-safe and unit-testable without a database.
 *
 * Authority boundaries (see docs/platform/ingestion/STAGING_CANARY.md):
 * - Production is unrepresentable: `production_write` is rejected here, and the
 *   durable schema has no production enum.
 * - The only accepted safety mode is `staging_write`, mapped to an
 *   `approved_write` shipment against a target whose resolved environment is
 *   `staging`.
 * - Approval requires an `ingestion_admin` (role `admin`) principal with a
 *   verified AAL2 MFA factor, a fresh step-up, and a non-empty audit reason.
 * - The actual target write happens elsewhere, only through the target adapter
 *   boundary. This module decides; it never writes.
 */

import type { AdminPrincipal } from "./admin-auth.js";
import type { ProgressiveRunReport } from "./progressive-run.js";
import type { ApprovalRequirement, SafetyMode } from "./schedule-proposal.js";

/** Default hard upper bound on rows written by a first canary. */
export const STAGING_CANARY_MAX_ROWS = 50;

/** A fresh MFA step-up must be at most this old (mirrors IP-11 admin-auth). */
export const STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS = 5 * 60 * 1000;

/** Only `staging` is ever allowed to be written; anything else is rejected. */
export type CanaryEnvironment = "staging" | "production" | (string & {});

export type StagingCanaryBlockCode =
  | "invalid_transition"
  | "production_write_forbidden"
  | "unsupported_safety_mode"
  | "not_staging_environment"
  | "run_not_reviewed"
  | "diff_incompatible"
  | "dry_run_invariant_violated"
  | "role_denied"
  | "scope_denied"
  | "mfa_required"
  | "fresh_step_up_required"
  | "audit_reason_required"
  | "delete_not_allowed"
  | "scope_not_narrow"
  | "row_bound_exceeded"
  | "nothing_to_ship";

export interface StagingCanaryBlock {
  code: StagingCanaryBlockCode;
  message: string;
}

export interface StagingCanaryApprovalContext {
  principal: AdminPrincipal;
  /** Operator's audit reason; recorded verbatim. Must be non-empty. */
  auditReason: string;
  now?: string;
  freshStepUpWindowMs?: number;
}

export interface StagingCanaryBounds {
  /** Defaults to STAGING_CANARY_MAX_ROWS. */
  maxRows?: number;
  /** Exactly one narrow geography. */
  geography: string;
  /** Exactly one narrow POI/category band. */
  category: string;
}

export interface EvaluateStagingCanaryPromotionInput {
  runReport: ProgressiveRunReport;
  transition: { from: "review_required"; to: SafetyMode };
  targetEnvironment: CanaryEnvironment;
  approval: StagingCanaryApprovalContext;
  bounds: StagingCanaryBounds;
}

export interface StagingCanaryWriteSummary {
  insert: number;
  update: number;
  noOp: number;
  total: number;
  /** Rows that actually mutate the target (insert + update). */
  writeCount: number;
}

export interface StagingCanaryApprover {
  provider: string;
  userId: string;
  email: string;
  role: AdminPrincipal["role"];
  assuranceLevel: AdminPrincipal["assuranceLevel"];
}

export interface StagingCanaryPlan {
  projectKey: string;
  targetId: string;
  sourceId: string;
  fromStatus: "review_required";
  safetyMode: "staging_write";
  shipmentMode: "approved_write";
  environment: "staging";
  bounds: { maxRows: number; geography: string; category: string };
  write: StagingCanaryWriteSummary;
  approval: ApprovalRequirement;
  approvedBy: StagingCanaryApprover;
  auditReason: string;
  approvedAt: string;
}

export type EvaluateStagingCanaryPromotionResult =
  | { ok: true; plan: StagingCanaryPlan; blocks: [] }
  | { ok: false; blocks: StagingCanaryBlock[] };

/**
 * Evaluate a `review_required -> staging_write` promotion. Returns either an
 * accepted, bounded plan or the full, ordered list of blocking reasons (so the
 * dashboard can explain exactly why a promotion is refused). Deterministic: the
 * same input always yields the same result.
 */
export function evaluateStagingCanaryPromotion(
  input: EvaluateStagingCanaryPromotionInput
): EvaluateStagingCanaryPromotionResult {
  const blocks: StagingCanaryBlock[] = [];
  const { runReport, transition, targetEnvironment, approval, bounds } = input;
  const maxRows = bounds.maxRows ?? STAGING_CANARY_MAX_ROWS;
  const diff = runReport.shipmentDiff;
  const write = summarizeWrite(input);

  // 1. Transition legality.
  if (transition.from !== "review_required") {
    blocks.push({
      code: "invalid_transition",
      message: `Promotion must start from review_required, not "${transition.from}".`
    });
  }

  // 2/3. Safety-mode mapping. Production is forbidden; only staging_write maps
  // to an approved_write staging shipment.
  if (transition.to === "production_write") {
    blocks.push({
      code: "production_write_forbidden",
      message: "production_write is forbidden and has no durable representation; production is blocked."
    });
  } else if (transition.to !== "staging_write") {
    blocks.push({
      code: "unsupported_safety_mode",
      message: `Only staging_write is promotable here; received "${transition.to}".`
    });
  }

  // 4. Staging-only environment.
  if (targetEnvironment !== "staging") {
    blocks.push({
      code: "not_staging_environment",
      message: `Resolved target environment must be staging, not "${targetEnvironment}".`
    });
  }

  // 5/6/7. Reviewed dry-run invariants.
  if (!runReport.reachedReview) {
    blocks.push({
      code: "run_not_reviewed",
      message: "The dry run has not reached review_required; nothing is promotable."
    });
  }
  if (!diff.compatible || diff.incompatibilities > 0) {
    blocks.push({
      code: "diff_incompatible",
      message: `The reviewed shipment diff is not compatible (${diff.incompatibilities} incompatibility/ies).`
    });
  }
  if (runReport.wroteToTarget !== false) {
    blocks.push({
      code: "dry_run_invariant_violated",
      message: "Dry-run invariant violated: the reviewed run claims a prior target write."
    });
  }

  // 8/9/10/11/12. Approval gate (ingestion_admin + AAL2 MFA + fresh step-up +
  // audit reason), mirroring IP-11 admin-auth semantics.
  if (approval.principal.role !== "admin") {
    blocks.push({
      code: "role_denied",
      message: "Staging-canary promotion requires an ingestion_admin (role=admin) principal."
    });
  }
  if (!hasProjectScope(approval.principal.scopes, runReport.projectKey)) {
    blocks.push({
      code: "scope_denied",
      message: `Principal lacks scope for project "${runReport.projectKey}".`
    });
  }
  if (!hasVerifiedAal2(approval.principal)) {
    blocks.push({
      code: "mfa_required",
      message: "A verified AAL2 MFA factor is required to promote a staging canary."
    });
  }
  if (!hasFreshStepUp(approval)) {
    blocks.push({
      code: "fresh_step_up_required",
      message: "A fresh MFA step-up is required to promote a staging canary."
    });
  }
  if (approval.auditReason.trim().length === 0) {
    blocks.push({
      code: "audit_reason_required",
      message: "A non-empty audit reason is required to promote a staging canary."
    });
  }

  // 13/14/15/16. Canary bounds.
  if (diff.delete > 0) {
    blocks.push({
      code: "delete_not_allowed",
      message: `A canary shipment must not delete rows; diff contains ${diff.delete} delete(s).`
    });
  }
  if (!isNarrowScopeValue(bounds.geography) || !isNarrowScopeValue(bounds.category)) {
    blocks.push({
      code: "scope_not_narrow",
      message: "Canary bounds must declare exactly one narrow geography and one narrow category."
    });
  }
  if (write.writeCount > maxRows) {
    blocks.push({
      code: "row_bound_exceeded",
      message: `Canary writes ${write.writeCount} rows, exceeding the bound of ${maxRows}.`
    });
  }
  if (write.total === 0) {
    blocks.push({
      code: "nothing_to_ship",
      message: "The reviewed diff has no shipment items; there is nothing to canary."
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const approvedAt = approval.now ?? new Date().toISOString();
  return {
    ok: true,
    blocks: [],
    plan: {
      projectKey: runReport.projectKey,
      targetId: runReport.targetId,
      sourceId: runReport.sourceId,
      fromStatus: "review_required",
      safetyMode: "staging_write",
      shipmentMode: "approved_write",
      environment: "staging",
      bounds: { maxRows, geography: bounds.geography, category: bounds.category },
      write,
      approval: {
        required: true,
        role: "ingestion_admin",
        requireMfa: true,
        requireAuditReason: true,
        description:
          "Approved staging canary: review_required -> staging_write (approved_write into Vamo staging)."
      },
      approvedBy: {
        provider: approval.principal.provider,
        userId: approval.principal.userId,
        email: approval.principal.email,
        role: approval.principal.role,
        assuranceLevel: approval.principal.assuranceLevel
      },
      auditReason: approval.auditReason.trim(),
      approvedAt
    }
  };
}

export function summarizeWrite(input: {
  runReport: ProgressiveRunReport;
}): StagingCanaryWriteSummary {
  const diff = input.runReport.shipmentDiff;
  return {
    insert: diff.insert,
    update: diff.update,
    noOp: diff.noOp,
    total: diff.total,
    writeCount: diff.insert + diff.update
  };
}

function hasVerifiedAal2(principal: AdminPrincipal): boolean {
  if (!principal.mfaRequired) {
    // IP-16 requires MFA regardless; a principal that is not MFA-required is not
    // sufficient for a destructive staging write.
    return false;
  }
  return principal.hasVerifiedMfaFactor && principal.assuranceLevel === "aal2";
}

function hasFreshStepUp(approval: StagingCanaryApprovalContext): boolean {
  const satisfiedAt = approval.principal.stepUpSatisfiedAt;
  if (!satisfiedAt) {
    return false;
  }
  const nowMs = Date.parse(approval.now ?? new Date().toISOString());
  const satisfiedMs = Date.parse(satisfiedAt);
  if (!Number.isFinite(nowMs) || !Number.isFinite(satisfiedMs)) {
    return false;
  }
  const windowMs = approval.freshStepUpWindowMs ?? STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS;
  return nowMs - satisfiedMs >= 0 && nowMs - satisfiedMs <= windowMs;
}

function hasProjectScope(scopes: string[], projectKey: string): boolean {
  return scopes.includes("*") || scopes.includes(projectKey);
}

/** A narrow scope value is non-empty, not a wildcard, and not a multi-value list. */
function isNarrowScopeValue(value: string): boolean {
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed === "*") {
    return false;
  }
  return !/[,;|]/.test(trimmed);
}
