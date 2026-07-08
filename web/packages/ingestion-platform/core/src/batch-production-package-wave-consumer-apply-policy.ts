/**
 * Pure consumer apply policy for production package waves (IP-18.6.6).
 */

import {
  ADMIN_FRESH_STEP_UP_CLOCK_SKEW_MS,
  type AdminPrincipal
} from "./admin-auth.js";
import { PRODUCTION_INBOX_FRESH_STEP_UP_WINDOW_MS } from "./production-inbox-policy.js";
import type { ProductionInboxApplyPreflight } from "../../adapters/target/src/postgres-production-inbox-apply.js";

export type ProductionPackageConsumerApplyBlockCode =
  | "role_denied"
  | "scope_denied"
  | "mfa_required"
  | "fresh_step_up_required"
  | "audit_reason_required"
  | "package_id_required"
  | "package_not_found"
  | "shipment_not_delivered"
  | "no_pending_items"
  | "already_applied"
  | "apply_not_configured";

export interface ProductionPackageConsumerApplyBlock {
  code: ProductionPackageConsumerApplyBlockCode;
  message: string;
}

export interface EvaluateProductionPackageConsumerApplyInput {
  projectKey: string;
  packageId: string;
  auditReason: string;
  principal: AdminPrincipal;
  preflight?: ProductionInboxApplyPreflight | null;
  applyDatabaseConfigured?: boolean;
  now?: string;
}

export type EvaluateProductionPackageConsumerApplyResult =
  | { ok: true }
  | { ok: false; blocks: ProductionPackageConsumerApplyBlock[] };

export function evaluateProductionPackageConsumerApply(
  input: EvaluateProductionPackageConsumerApplyInput
): EvaluateProductionPackageConsumerApplyResult {
  const blocks: ProductionPackageConsumerApplyBlock[] = [];
  const auditReason = input.auditReason.trim();
  const packageId = input.packageId.trim();
  const now = input.now ?? new Date().toISOString();

  if (input.applyDatabaseConfigured === false) {
    blocks.push({
      code: "apply_not_configured",
      message: "VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL is not configured for consumer apply."
    });
  }

  if (!packageId) {
    blocks.push({
      code: "package_id_required",
      message: "A non-empty packageId is required to apply a delivered production inbox package."
    });
  }

  if (input.principal.role !== "admin") {
    blocks.push({
      code: "role_denied",
      message: "Consumer apply requires an ingestion_admin (role=admin) principal."
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
      message: "Consumer apply requires verified MFA step-up (AAL2)."
    });
  }

  if (!hasFreshStepUp(input.principal, now)) {
    blocks.push({
      code: "fresh_step_up_required",
      message: "Consumer apply requires a fresh MFA step-up."
    });
  }

  if (!auditReason) {
    blocks.push({
      code: "audit_reason_required",
      message: "A non-empty audit reason is required to apply a delivered production inbox package."
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const preflightBlocks = evaluateProductionPackageConsumerApplyPreflight(input.preflight);
  if (preflightBlocks.length > 0) {
    return { ok: false, blocks: preflightBlocks };
  }

  return { ok: true };
}

export function evaluateProductionPackageConsumerApplyPreflight(
  preflight: ProductionInboxApplyPreflight | null | undefined
): ProductionPackageConsumerApplyBlock[] {
  if (!preflight) {
    return [
      {
        code: "package_not_found",
        message: "The production inbox package was not found for consumer apply preflight."
      }
    ];
  }

  if (
    preflight.shipmentStatus === "consumer_applied" ||
    (preflight.pendingItemCount === 0 &&
      countAppliedItems(preflight) === preflight.itemCount &&
      preflight.itemCount > 0)
  ) {
    return [
      {
        code: "already_applied",
        message: "The production inbox package has already been applied by the consumer."
      }
    ];
  }

  if (preflight.shipmentStatus !== "production_inbox_delivered") {
    return [
      {
        code: "shipment_not_delivered",
        message: `Consumer apply requires shipment status production_inbox_delivered; got ${preflight.shipmentStatus}.`
      }
    ];
  }

  if (preflight.pendingItemCount <= 0) {
    return [
      {
        code: "no_pending_items",
        message: "Consumer apply requires at least one pending shipment item."
      }
    ];
  }

  return [];
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
  return (
    ageMs >= -ADMIN_FRESH_STEP_UP_CLOCK_SKEW_MS &&
    ageMs <= PRODUCTION_INBOX_FRESH_STEP_UP_WINDOW_MS
  );
}

export function countAppliedItems(preflight: ProductionInboxApplyPreflight): number {
  return preflight.items.filter((item) => item.applyStatus === "applied").length;
}
