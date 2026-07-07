/**
 * Pure dashboard helpers for production package-wave approval (IP-18.6.2).
 */

import type { BatchQueueLatestProductionPackageWave, BatchQueueSnapshot } from "./batch-queue-read-model.js";
import type { BatchProductionPackageWaveBlockCode } from "./batch-production-package-wave-policy.js";
import { countStagingProvenPackageEligibleUnits } from "./batch-production-package-wave-policy.js";
import type { ProductionPackageStagingEvidence } from "./batch-production-package-wave-policy.js";

export type ProductionPackageWaveStatusTone = "neutral" | "good" | "watch" | "danger";

export interface ProductionPackageWaveStatusPresentation {
  label: string;
  tone: ProductionPackageWaveStatusTone;
  detail?: string;
}

export const PRODUCTION_PACKAGE_WAVE_BLOCK_LABELS: Record<BatchProductionPackageWaveBlockCode, string> = {
  not_staging_proven: "Unit is not staging_canary_succeeded.",
  not_production_environment: "Package wave target environment must be production.",
  legacy_target_key: "Target key must be environment-neutral.",
  schema_contract_mismatch: "Schema contract must be vamo-place-intelligence@1.",
  dry_run_invariant_violated: "Dry-run report must have wroteToTarget=false.",
  staging_canary_required: "Staging-canary evidence is required.",
  staging_canary_not_succeeded: "Staging-canary evidence must be succeeded.",
  active_blockers: "Active blockers remain on the queue item.",
  delete_not_allowed: "Deletes are not allowed in production package waves.",
  row_bound_exceeded: "Selected rows exceed the wave maxRows bound.",
  unit_bound_exceeded: "Selected units exceed the wave maxUnits bound.",
  package_bound_exceeded: "Selected packages exceed the wave maxPackages bound.",
  already_delivered_or_pending_apply: "Unit is already in an active or spent package wave.",
  approval_expired: "Package-wave approval has expired.",
  role_denied: "Requires the ingestion_admin role (admin).",
  scope_denied: "This admin account is not scoped to this ingestion project.",
  mfa_required: "Requires verified MFA step-up (AAL2).",
  fresh_step_up_required: "Requires a fresh MFA step-up.",
  audit_reason_required: "A non-empty audit reason is required.",
  max_units_invalid: "maxUnits must be a positive integer.",
  max_rows_invalid: "maxRows must be a positive integer.",
  max_packages_invalid: "maxPackages must be a positive integer.",
  first_wave_ramp_exceeded: "The first live production package wave is hard-capped at 1 unit / 1 package.",
  no_eligible_items: "No staging-proven units with valid evidence are available.",
  queue_status_drift: "Queue status drifted since approval.",
  dry_run_evidence_drift: "Dry-run evidence drifted since approval.",
  staging_evidence_drift: "Staging evidence drifted since approval.",
  schema_contract_drift: "Schema contract drifted since approval.",
  checksum_incompatible: "Package checksum evidence is incompatible."
};

export function describeProductionPackageWaveStatus(
  status: string
): ProductionPackageWaveStatusPresentation {
  switch (status) {
    case "production_package_ready":
      return { label: "Ready for package-wave approval", tone: "watch" };
    case "production_package_approved":
      return {
        label: "Approved (not delivered)",
        tone: "watch",
        detail: "Control-plane approval recorded; inbox delivery is a separate runbook step."
      };
    case "production_package_delivering":
      return { label: "Delivering to production inbox", tone: "watch" };
    case "production_package_delivered":
      return {
        label: "Delivered to production inbox",
        tone: "good",
        detail: "Package reached the consumer inbox; apply is consumer-owned."
      };
    case "consumer_apply_pending":
      return {
        label: "Consumer apply pending",
        tone: "watch",
        detail: "Package delivered; waiting for consumer-owned apply."
      };
    case "consumer_applied":
      return { label: "Consumer applied", tone: "good" };
    case "consumer_apply_failed":
      return {
        label: "Consumer apply failed",
        tone: "danger",
        detail: "Apply failed after delivery — this is not the same as already delivered."
      };
    case "production_package_blocked":
      return { label: "Blocked before delivery", tone: "danger" };
    case "approved":
      return { label: "Wave approved (control plane)", tone: "watch" };
    case "delivering":
      return { label: "Wave delivering", tone: "watch" };
    case "delivered":
      return { label: "Wave delivered", tone: "good" };
    case "expired":
      return {
        label: "Approval expired",
        tone: "danger",
        detail: "Approval freshness elapsed; queue units were released to staging_canary_succeeded."
      };
    case "released":
      return { label: "Released (approval expired)", tone: "neutral" };
    default:
      return { label: status.replaceAll("_", " "), tone: "neutral" };
  }
}

export function summarizeProductionPackageWaveDashboard(input: {
  snapshot: BatchQueueSnapshot;
  targetKey: string;
  stagingEvidenceByUnitKey: Readonly<Record<string, ProductionPackageStagingEvidence>>;
  latestWave?: BatchQueueLatestProductionPackageWave | null;
}): {
  eligibleCount: number;
  progress: BatchQueueSnapshot["progress"]["productionPackage"];
  latestWaveStatus?: ProductionPackageWaveStatusPresentation;
} {
  return {
    eligibleCount: countStagingProvenPackageEligibleUnits(
      input.snapshot,
      input.targetKey,
      input.stagingEvidenceByUnitKey
    ),
    progress: input.snapshot.progress.productionPackage,
    latestWaveStatus: input.latestWave
      ? describeProductionPackageWaveStatus(input.latestWave.status)
      : undefined
  };
}
