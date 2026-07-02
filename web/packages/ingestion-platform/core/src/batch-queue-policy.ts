/**
 * Pure batch-queue mutation policy (IP-18.3).
 *
 * Decides whether an operator may schedule the persisted batch queue for its
 * dry-run phase. This module has no DB, network, provider, or target access.
 */

import type { AdminPrincipal } from "./admin-auth.js";
import type { BatchQueueSnapshot } from "./batch-queue-read-model.js";

export type BatchQueueScheduleDryRunBlockCode =
  | "role_denied"
  | "scope_denied"
  | "mfa_required"
  | "audit_reason_required"
  | "unsafe_safety_mode"
  | "target_environment_required"
  | "no_eligible_items";

export interface BatchQueueScheduleDryRunBlock {
  code: BatchQueueScheduleDryRunBlockCode;
  message: string;
}

export interface BatchQueueScheduleDryRunPlan {
  action: "schedule_dry_run_batch";
  projectKey: string;
  queueId: string;
  planId: string;
  targetKey: string;
  targetEnvironment: string;
  sourceKey: string;
  fromStatus: "ready_for_dry_run";
  toStatus: "dry_run_ready";
  itemCount: number;
  unitKeys: string[];
  auditReason: string;
  approvedBy: {
    email: string;
    role: AdminPrincipal["role"];
    assuranceLevel: AdminPrincipal["assuranceLevel"];
  };
}

export type EvaluateBatchQueueScheduleDryRunResult =
  | { ok: true; plan: BatchQueueScheduleDryRunPlan }
  | { ok: false; blocks: BatchQueueScheduleDryRunBlock[] };

export interface EvaluateBatchQueueScheduleDryRunInput {
  projectKey: string;
  snapshot: BatchQueueSnapshot;
  principal: AdminPrincipal;
  auditReason: string;
}

export function evaluateBatchQueueScheduleDryRun(
  input: EvaluateBatchQueueScheduleDryRunInput
): EvaluateBatchQueueScheduleDryRunResult {
  const blocks: BatchQueueScheduleDryRunBlock[] = [];
  const auditReason = input.auditReason.trim();

  if (input.principal.role !== "operator" && input.principal.role !== "admin") {
    blocks.push({
      code: "role_denied",
      message: "Scheduling a batch dry run requires the operator or admin role."
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
      message: "Scheduling a batch dry run requires MFA step-up (AAL2)."
    });
  }

  if (!auditReason) {
    blocks.push({
      code: "audit_reason_required",
      message: "A non-empty audit reason is required to schedule a batch dry run."
    });
  }

  if (input.snapshot.safetyMode !== "dry_run") {
    blocks.push({
      code: "unsafe_safety_mode",
      message: "Batch queue scheduling may only advance dry_run plans."
    });
  }

  if (!input.snapshot.targetEnvironment) {
    blocks.push({
      code: "target_environment_required",
      message: "Batch queue scheduling requires an explicit target environment."
    });
  }

  const unitKeys = input.snapshot.items
    .filter((item) => item.status === "ready_for_dry_run")
    .map((item) => item.unitKey);
  if (unitKeys.length === 0) {
    blocks.push({
      code: "no_eligible_items",
      message: "There are no ready_for_dry_run queue items to schedule."
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  return {
    ok: true,
    plan: {
      action: "schedule_dry_run_batch",
      projectKey: input.projectKey,
      queueId: input.snapshot.queueId,
      planId: input.snapshot.planId,
      targetKey: input.snapshot.targetKey,
      targetEnvironment: input.snapshot.targetEnvironment,
      sourceKey: input.snapshot.sourceKey,
      fromStatus: "ready_for_dry_run",
      toStatus: "dry_run_ready",
      itemCount: unitKeys.length,
      unitKeys,
      auditReason,
      approvedBy: {
        email: input.principal.email,
        role: input.principal.role,
        assuranceLevel: input.principal.assuranceLevel
      }
    }
  };
}

function principalHasProjectScope(principal: AdminPrincipal, projectKey: string): boolean {
  return principal.scopes.includes("*") || principal.scopes.includes(projectKey);
}
