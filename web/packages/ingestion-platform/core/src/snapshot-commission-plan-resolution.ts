/**
 * Server-derived snapshot commissioning plan resolution (IP-18.8.13).
 *
 * Prefers the active autonomy policy's explicit batch plan key, otherwise falls
 * back to the queue workflow's server-selected active plan.
 */

export type SnapshotCommissionPlanResolutionSource = "autonomy_policy" | "queue_context";

export type SnapshotCommissionPlanResolutionCode =
  | "plan_not_found"
  | "commission_plan_context_mismatch";

export type SnapshotCommissionPlanResolutionResult =
  | {
      ok: true;
      planKey: string;
      source: SnapshotCommissionPlanResolutionSource;
    }
  | {
      ok: false;
      code: SnapshotCommissionPlanResolutionCode;
    };

export function evaluateSnapshotCommissionPlanResolution(input: {
  policyBatchPlanKey?: string;
  queuePlanKey?: string;
}): SnapshotCommissionPlanResolutionResult {
  const policyBatchPlanKey = input.policyBatchPlanKey?.trim();
  const queuePlanKey = input.queuePlanKey?.trim();

  if (policyBatchPlanKey) {
    if (queuePlanKey && queuePlanKey !== policyBatchPlanKey) {
      return { ok: false, code: "commission_plan_context_mismatch" };
    }
    return { ok: true, planKey: policyBatchPlanKey, source: "autonomy_policy" };
  }

  if (queuePlanKey) {
    return { ok: true, planKey: queuePlanKey, source: "queue_context" };
  }

  return { ok: false, code: "plan_not_found" };
}
