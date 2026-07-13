/**
 * Resolves the effective delivery lifecycle for a scope that appears in more
 * than one batch plan. This is read-model evidence only; it never changes the
 * plan-local queue status or package-wave state.
 */

export const CROSS_PLAN_PACKAGE_LIFECYCLE_STATUSES = [
  "approved",
  "delivering",
  "delivered",
  "consumer_apply_pending",
  "consumer_applied",
  "consumer_apply_failed"
] as const;

export type CrossPlanPackageLifecycleStatus =
  (typeof CROSS_PLAN_PACKAGE_LIFECYCLE_STATUSES)[number];

export interface CrossPlanPackageLifecycle {
  status: CrossPlanPackageLifecycleStatus;
  planKey: string;
  waveKey: string;
}

export interface CrossPlanPackageLifecycleCandidate extends CrossPlanPackageLifecycle {
  unitKey: string;
  updatedAt?: string | Date | null;
}

const STATUS_PRIORITY: Record<CrossPlanPackageLifecycleStatus, number> = {
  approved: 1,
  delivering: 2,
  delivered: 3,
  consumer_apply_pending: 4,
  consumer_apply_failed: 5,
  consumer_applied: 6
};

export function isCrossPlanPackageLifecycleStatus(
  value: string
): value is CrossPlanPackageLifecycleStatus {
  return (CROSS_PLAN_PACKAGE_LIFECYCLE_STATUSES as readonly string[]).includes(value);
}

export function resolveCrossPlanPackageLifecycles(
  candidates: readonly CrossPlanPackageLifecycleCandidate[]
): Record<string, CrossPlanPackageLifecycle> {
  const selected = new Map<string, CrossPlanPackageLifecycleCandidate>();

  for (const candidate of candidates) {
    const existing = selected.get(candidate.unitKey);
    if (!existing || shouldReplaceLifecycle(existing, candidate)) {
      selected.set(candidate.unitKey, candidate);
    }
  }

  return Object.fromEntries(
    [...selected.entries()].map(([unitKey, candidate]) => [
      unitKey,
      {
        status: candidate.status,
        planKey: candidate.planKey,
        waveKey: candidate.waveKey
      }
    ])
  );
}

function shouldReplaceLifecycle(
  current: CrossPlanPackageLifecycleCandidate,
  candidate: CrossPlanPackageLifecycleCandidate
): boolean {
  const candidateUpdatedAt = toTimestamp(candidate.updatedAt);
  const currentUpdatedAt = toTimestamp(current.updatedAt);
  if (candidateUpdatedAt !== currentUpdatedAt) {
    return candidateUpdatedAt > currentUpdatedAt;
  }
  return STATUS_PRIORITY[candidate.status] > STATUS_PRIORITY[current.status];
}

function toTimestamp(value: string | Date | null | undefined): number {
  if (value instanceof Date) {
    return Number.isFinite(value.getTime()) ? value.getTime() : 0;
  }
  if (typeof value !== "string") {
    return 0;
  }
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : 0;
}
