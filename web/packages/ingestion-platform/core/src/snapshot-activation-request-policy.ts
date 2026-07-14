/** Operator policy for creating snapshot activation requests (IP-18.8.14). */
import type { AdminAssuranceLevel, AdminRole } from "./admin-auth.js";
import type { CommandActorType } from "./commands.js";

export type SnapshotActivationRequestBlockCode =
  | "missing_audit_reason"
  | "missing_actor_identity"
  | "actor_not_admin"
  | "fresh_step_up_required"
  | "activation_not_ready"
  | "activation_request_already_active";

export interface EvaluateSnapshotActivationRequestCreateInput {
  actor: {
    type: CommandActorType;
    id: string;
    role?: AdminRole;
    assuranceLevel?: AdminAssuranceLevel;
    stepUpFresh?: boolean;
  };
  auditReason: string;
  activationReady: boolean;
  hasActiveRequest: boolean;
}

export type EvaluateSnapshotActivationRequestCreateResult =
  | { ok: true; auditReason: string }
  | { ok: false; blocks: Array<{ code: SnapshotActivationRequestBlockCode; message: string }> };

export function evaluateSnapshotActivationRequestCreate(
  input: EvaluateSnapshotActivationRequestCreateInput
): EvaluateSnapshotActivationRequestCreateResult {
  const blocks: Array<{ code: SnapshotActivationRequestBlockCode; message: string }> = [];
  if (!input.auditReason.trim()) {
    blocks.push({ code: "missing_audit_reason", message: "Activation requests require an audit reason." });
  }
  if (!input.actor.id.trim()) {
    blocks.push({ code: "missing_actor_identity", message: "Activation requests require a named operator actor." });
  }
  if (input.actor.type !== "operator" || input.actor.role !== "admin") {
    blocks.push({ code: "actor_not_admin", message: "Activation requests require an admin operator." });
  }
  if (input.actor.assuranceLevel !== "aal2" || input.actor.stepUpFresh !== true) {
    blocks.push({ code: "fresh_step_up_required", message: "Activation requests require a fresh AAL2 operator step-up." });
  }
  if (!input.activationReady) {
    blocks.push({ code: "activation_not_ready", message: "A registered release must be activation pending before it can be activated." });
  }
  if (input.hasActiveRequest) {
    blocks.push({ code: "activation_request_already_active", message: "An activation request is already active for this batch plan." });
  }
  return blocks.length > 0
    ? { ok: false, blocks }
    : { ok: true, auditReason: input.auditReason.trim() };
}
