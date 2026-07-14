/**
 * Operator policy for snapshot release commissioning requests (IP-18.8.13).
 */

import type { AdminAssuranceLevel, AdminRole } from "./admin-auth.js";
import type { CommandActorType } from "./commands.js";

export type SnapshotCommissionRequestBlockCode =
  | "missing_audit_reason"
  | "missing_actor_identity"
  | "actor_not_admin"
  | "fresh_step_up_required"
  | "commission_request_already_active";

export interface EvaluateSnapshotCommissionRequestCreateInput {
  actor: {
    type: CommandActorType;
    id: string;
    role?: AdminRole;
    assuranceLevel?: AdminAssuranceLevel;
    stepUpFresh?: boolean;
  };
  auditReason: string;
  hasActiveRequest: boolean;
}

export type EvaluateSnapshotCommissionRequestCreateResult =
  | { ok: true; auditReason: string }
  | {
      ok: false;
      blocks: Array<{
        code: SnapshotCommissionRequestBlockCode;
        message: string;
      }>;
    };

export function evaluateSnapshotCommissionRequestCreate(
  input: EvaluateSnapshotCommissionRequestCreateInput
): EvaluateSnapshotCommissionRequestCreateResult {
  const blocks: Array<{
    code: SnapshotCommissionRequestBlockCode;
    message: string;
  }> = [];

  if (input.auditReason.trim().length === 0) {
    blocks.push({
      code: "missing_audit_reason",
      message: "Commissioning requests require an audit reason."
    });
  }

  if (!input.actor.id.trim()) {
    blocks.push({
      code: "missing_actor_identity",
      message: "Commissioning requests require a named operator actor."
    });
  }

  if (input.actor.type !== "operator" || input.actor.role !== "admin") {
    blocks.push({
      code: "actor_not_admin",
      message: "Commissioning requests require an admin operator."
    });
  }

  if (input.actor.assuranceLevel !== "aal2" || input.actor.stepUpFresh !== true) {
    blocks.push({
      code: "fresh_step_up_required",
      message: "Commissioning requests require a fresh AAL2 operator step-up."
    });
  }

  if (input.hasActiveRequest) {
    blocks.push({
      code: "commission_request_already_active",
      message: "An active commissioning request already exists for this batch plan."
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  return { ok: true, auditReason: input.auditReason.trim() };
}
