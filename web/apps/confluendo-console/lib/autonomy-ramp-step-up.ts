import {
  ADMIN_FRESH_STEP_UP_CLOCK_SKEW_MS,
  ADMIN_FRESH_STEP_UP_WINDOW_MS,
  type AdminPrincipal
} from "@confluendo/ingestion-platform/admin-auth";

export function hasFreshAdminStepUp(principal: AdminPrincipal, now = new Date().toISOString()): boolean {
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
  return ageMs >= -ADMIN_FRESH_STEP_UP_CLOCK_SKEW_MS && ageMs <= ADMIN_FRESH_STEP_UP_WINDOW_MS;
}
