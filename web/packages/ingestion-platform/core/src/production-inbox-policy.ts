/**
 * Production-inbox approval policy (IP-17) — pure, deterministic, DB-free.
 *
 * Decides whether a reviewed dry run that has already passed a staging canary
 * may be promoted to the Vamo-owned production inbox. This policy never writes
 * to a target and never applies product rows; it only returns a delivery intent
 * for the confirmation-gated runbook.
 */

import {
  ADMIN_FRESH_STEP_UP_CLOCK_SKEW_MS,
  ADMIN_FRESH_STEP_UP_WINDOW_MS,
  type AdminPrincipal
} from "./admin-auth.js";
import type { ProgressiveRunReport } from "./progressive-run.js";
import type { ApprovalRequirement } from "./schedule-proposal.js";
import { summarizeWrite, type StagingCanaryWriteSummary } from "./staging-canary-policy.js";

export const PRODUCTION_INBOX_MAX_ROWS = 500;
export const PRODUCTION_INBOX_FRESH_STEP_UP_WINDOW_MS = ADMIN_FRESH_STEP_UP_WINDOW_MS;
export const PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS = 15 * 60 * 1000;

export type ProductionInboxTransition = {
  from: "approved_for_production_inbox";
  to: "production_inbox_delivered";
};

export type ProductionInboxBlockCode =
  | "invalid_transition"
  | "not_production_environment"
  | "run_not_reviewed"
  | "diff_incompatible"
  | "dry_run_invariant_violated"
  | "staging_canary_required"
  | "staging_canary_not_succeeded"
  | "role_denied"
  | "scope_denied"
  | "mfa_required"
  | "fresh_step_up_required"
  | "audit_reason_required"
  | "delete_not_allowed"
  | "scope_not_narrow"
  | "row_bound_exceeded"
  | "nothing_to_deliver";

export interface ProductionInboxBlock {
  code: ProductionInboxBlockCode;
  message: string;
}

export interface ProductionInboxStagingEvidence {
  status: string;
  shipmentKey?: string;
  approvalAuditId?: string;
}

export interface ProductionInboxApprovalContext {
  principal: AdminPrincipal;
  auditReason: string;
  now?: string;
  freshStepUpWindowMs?: number;
}

export interface ProductionInboxBounds {
  maxRows?: number;
  geography: string;
  category: string;
}

export interface EvaluateProductionInboxPromotionInput {
  runReport: ProgressiveRunReport;
  transition: ProductionInboxTransition;
  targetEnvironment: string;
  stagingCanary?: ProductionInboxStagingEvidence | null;
  approval: ProductionInboxApprovalContext;
  bounds: ProductionInboxBounds;
}

export interface ProductionInboxApprover {
  provider: string;
  userId: string;
  email: string;
  role: AdminPrincipal["role"];
  assuranceLevel: AdminPrincipal["assuranceLevel"];
}

export interface ProductionInboxPlan {
  projectKey: string;
  targetId: string;
  sourceId: string;
  fromStatus: "approved_for_production_inbox";
  toStatus: "production_inbox_delivered";
  targetEnvironment: "production";
  shipmentMode: "approved_write";
  schemaContract: "vamo-place-intelligence@1";
  bounds: { maxRows: number; geography: string; category: string };
  write: StagingCanaryWriteSummary;
  stagingCanary: ProductionInboxStagingEvidence;
  approval: ApprovalRequirement;
  approvedBy: ProductionInboxApprover;
  auditReason: string;
  approvedAt: string;
}

export type EvaluateProductionInboxPromotionResult =
  | { ok: true; plan: ProductionInboxPlan; blocks: [] }
  | { ok: false; blocks: ProductionInboxBlock[] };

const SUCCEEDED_CANARY_STATUSES = new Set(["succeeded"]);

export function evaluateProductionInboxPromotion(
  input: EvaluateProductionInboxPromotionInput
): EvaluateProductionInboxPromotionResult {
  const blocks: ProductionInboxBlock[] = [];
  const { runReport, transition, approval, bounds } = input;
  const diff = runReport.shipmentDiff;
  const write = summarizeWrite({ runReport });
  const maxRows = bounds.maxRows ?? PRODUCTION_INBOX_MAX_ROWS;

  if (
    transition.from !== "approved_for_production_inbox" ||
    transition.to !== "production_inbox_delivered"
  ) {
    blocks.push({
      code: "invalid_transition",
      message:
        "Production inbox delivery must use approved_for_production_inbox -> production_inbox_delivered."
    });
  }

  if (input.targetEnvironment !== "production") {
    blocks.push({
      code: "not_production_environment",
      message: `Production inbox delivery requires targetEnvironment=production, not "${input.targetEnvironment}".`
    });
  }

  if (!runReport.reachedReview) {
    blocks.push({
      code: "run_not_reviewed",
      message: "The dry run has not reached review_required; nothing can be delivered."
    });
  }
  if (!diff.compatible || diff.incompatibilities > 0) {
    blocks.push({
      code: "diff_incompatible",
      message: `The reviewed diff is incompatible (${diff.incompatibilities} incompatibility/ies).`
    });
  }
  if (runReport.wroteToTarget !== false) {
    blocks.push({
      code: "dry_run_invariant_violated",
      message: "Dry-run invariant violated: the reviewed run reports a target write."
    });
  }

  if (!input.stagingCanary) {
    blocks.push({
      code: "staging_canary_required",
      message: "A succeeded staging canary shipment is required before production inbox delivery."
    });
  } else if (!SUCCEEDED_CANARY_STATUSES.has(input.stagingCanary.status)) {
    blocks.push({
      code: "staging_canary_not_succeeded",
      message: `The staging canary is "${input.stagingCanary.status}", not succeeded.`
    });
  }

  if (approval.principal.role !== "admin") {
    blocks.push({
      code: "role_denied",
      message: "Production inbox delivery requires an ingestion_admin (role=admin) principal."
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
      message: "A verified AAL2 MFA factor is required to approve production inbox delivery."
    });
  }
  if (!hasFreshStepUp(approval)) {
    blocks.push({
      code: "fresh_step_up_required",
      message: "A fresh MFA step-up is required to approve production inbox delivery."
    });
  }
  if (approval.auditReason.trim().length === 0) {
    blocks.push({
      code: "audit_reason_required",
      message: "A non-empty audit reason is required to approve production inbox delivery."
    });
  }

  if (diff.delete > 0) {
    blocks.push({
      code: "delete_not_allowed",
      message: `Production inbox delivery must not include deletes; diff has ${diff.delete}.`
    });
  }
  if (!isNarrowScopeValue(bounds.geography) || !isNarrowScopeValue(bounds.category)) {
    blocks.push({
      code: "scope_not_narrow",
      message: "Production inbox delivery must carry one narrow geography and one narrow category."
    });
  }
  if (write.writeCount > maxRows) {
    blocks.push({
      code: "row_bound_exceeded",
      message: `Production inbox delivery writes ${write.writeCount} rows, exceeding the bound of ${maxRows}.`
    });
  }
  if (write.total === 0) {
    blocks.push({
      code: "nothing_to_deliver",
      message: "The reviewed diff has no shipment items; there is nothing to deliver."
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
      fromStatus: "approved_for_production_inbox",
      toStatus: "production_inbox_delivered",
      targetEnvironment: "production",
      shipmentMode: "approved_write",
      schemaContract: "vamo-place-intelligence@1",
      bounds: { maxRows, geography: bounds.geography, category: bounds.category },
      write,
      stagingCanary: input.stagingCanary!,
      approval: {
        required: true,
        role: "ingestion_admin",
        requireMfa: true,
        requireAuditReason: true,
        description:
          "Approved production inbox delivery: Confluendo may deliver the package to confluendo_inbox; Vamo applies separately."
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

export function isProductionInboxApprovalFresh(input: {
  approvedAt: string;
  now: string;
  maxAgeMs?: number;
}): boolean {
  const approvedMs = Date.parse(input.approvedAt);
  const nowMs = Date.parse(input.now);
  if (!Number.isFinite(approvedMs) || !Number.isFinite(nowMs)) {
    return false;
  }
  const ageMs = nowMs - approvedMs;
  return ageMs >= 0 && ageMs <= (input.maxAgeMs ?? PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS);
}

function hasVerifiedAal2(principal: AdminPrincipal): boolean {
  return principal.mfaRequired && principal.hasVerifiedMfaFactor && principal.assuranceLevel === "aal2";
}

function hasFreshStepUp(approval: ProductionInboxApprovalContext): boolean {
  const satisfiedAt = approval.principal.stepUpSatisfiedAt;
  if (!satisfiedAt) {
    return false;
  }
  const nowMs = Date.parse(approval.now ?? new Date().toISOString());
  const satisfiedMs = Date.parse(satisfiedAt);
  if (!Number.isFinite(nowMs) || !Number.isFinite(satisfiedMs)) {
    return false;
  }
  const ageMs = nowMs - satisfiedMs;
  return (
    ageMs >= -ADMIN_FRESH_STEP_UP_CLOCK_SKEW_MS &&
    ageMs <= (approval.freshStepUpWindowMs ?? PRODUCTION_INBOX_FRESH_STEP_UP_WINDOW_MS)
  );
}

function hasProjectScope(scopes: string[], projectKey: string): boolean {
  return scopes.includes("*") || scopes.includes(projectKey);
}

function isNarrowScopeValue(value: string): boolean {
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed !== "*" && !/[,;|]/.test(trimmed);
}
