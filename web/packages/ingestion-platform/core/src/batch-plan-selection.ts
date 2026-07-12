/**
 * Autonomy drain batch plan selection — pure helper (IP-18.8.3).
 *
 * Resolves which persisted batch plan autonomy should drain. Policy summary may
 * pin an explicit plan key; callers may override for hosted scheduler env/CLI.
 */

import type { AutonomyPolicyEnvelope } from "./autonomy-policy.js";

export const AUTONOMY_POLICY_BATCH_PLAN_KEY = "batchPlanKey";

export function readAutonomyBatchPlanKeyFromSummary(
  summary?: Record<string, unknown> | null
): string | undefined {
  if (!summary) {
    return undefined;
  }
  const candidates = [
    summary[AUTONOMY_POLICY_BATCH_PLAN_KEY],
    summary.queuePlanKey,
    summary.batch_plan_key
  ];
  for (const candidate of candidates) {
    if (typeof candidate === "string" && candidate.trim().length > 0) {
      return candidate.trim();
    }
  }
  return undefined;
}

export function resolveAutonomyDrainBatchPlanKey(input: {
  policy: Pick<AutonomyPolicyEnvelope, "batchPlanKey" | "summary">;
  batchPlanKey?: string;
}): string | undefined {
  const override = input.batchPlanKey?.trim();
  if (override) {
    return override;
  }
  if (input.policy.batchPlanKey?.trim()) {
    return input.policy.batchPlanKey.trim();
  }
  return readAutonomyBatchPlanKeyFromSummary(input.policy.summary);
}
