import type { BatchQueueItem, BatchQueueItemStatus } from "@confluendo/ingestion-platform/core";
import type { IngestionStatus, IngestionTone } from "@/content/ingestion-dashboard";

export type OperatorTone = "good" | "watch" | "danger" | "info" | "neutral";

export const CONSOLE_VIEWS = [
  "overview",
  "queue",
  "agent",
  "staging",
  "delivery",
  "diagnostics"
] as const;

export type ConsoleView = (typeof CONSOLE_VIEWS)[number];

export const consoleViewLabels: Record<ConsoleView, string> = {
  overview: "Overview",
  queue: "Queue",
  agent: "Agent",
  staging: "Staging",
  delivery: "Delivery",
  diagnostics: "Diagnostics"
};

export const statusLabels: Record<IngestionStatus, string> = {
  running: "Running",
  paused: "Paused",
  stopped: "Stopped",
  blocked: "Blocked",
  queued: "Queued",
  complete: "Complete"
};

export const toneLabels: Record<IngestionTone, string> = {
  good: "Healthy",
  watch: "Watch",
  danger: "Needs action",
  neutral: "Info"
};

export const queueStatusLabels: Record<BatchQueueItemStatus, string> = {
  planned: "Planned",
  blocked: "Blocked",
  ready_for_dry_run: "Ready to simulate",
  dry_run_ready: "Simulation queued",
  dry_run_running: "Simulating",
  dry_run_succeeded: "Simulation passed",
  dry_run_blocked: "Simulation blocked",
  staging_canary_ready: "Ready for staging",
  staging_canary_approved: "Staging approved",
  staging_canary_running: "Writing to staging",
  staging_canary_succeeded: "Staging verified",
  staging_canary_blocked: "Staging blocked",
  staged_ready: "Ready after staging",
  production_ready: "Ready for delivery",
  applied: "Applied",
  production_package_ready: "Ready for delivery",
  production_package_approved: "Delivery approved",
  production_package_delivering: "Delivering",
  production_package_delivered: "Delivered to inbox",
  consumer_apply_pending: "Waiting for consumer apply",
  consumer_applied: "Applied by consumer",
  consumer_apply_failed: "Consumer apply failed",
  production_package_blocked: "Delivery blocked"
};

export const queueStatusTones: Record<BatchQueueItemStatus, OperatorTone> = {
  planned: "neutral",
  blocked: "danger",
  ready_for_dry_run: "info",
  dry_run_ready: "info",
  dry_run_running: "info",
  dry_run_succeeded: "good",
  dry_run_blocked: "danger",
  staging_canary_ready: "info",
  staging_canary_approved: "watch",
  staging_canary_running: "info",
  staging_canary_succeeded: "good",
  staging_canary_blocked: "danger",
  staged_ready: "good",
  production_ready: "info",
  applied: "good",
  production_package_ready: "info",
  production_package_approved: "watch",
  production_package_delivering: "info",
  production_package_delivered: "info",
  consumer_apply_pending: "watch",
  consumer_applied: "good",
  consumer_apply_failed: "danger",
  production_package_blocked: "danger"
};

export interface StatusSlice {
  label: string;
  value: number;
  percent: number;
  tone: OperatorTone;
}

export function lifecycleStage(status: BatchQueueItemStatus): string {
  if (status === "planned") {
    return "Planned";
  }
  if (status === "blocked" || status.endsWith("_blocked")) {
    return "Exception";
  }
  if (status.startsWith("dry_run") || status === "ready_for_dry_run") {
    return "Simulation";
  }
  if (status.startsWith("staging_canary") || status === "staged_ready") {
    return "Staging verification";
  }
  if (status.startsWith("production_package") || status === "production_ready") {
    return "Consumer inbox delivery";
  }
  if (status.startsWith("consumer_") || status === "applied") {
    return "Consumer apply";
  }
  return "Other";
}

export function buildStatusDistribution(items: readonly BatchQueueItem[]): StatusSlice[] {
  const slices = [
    {
      label: "Simulation",
      value: items.filter(
        (item) => item.status.startsWith("dry_run") || item.status === "ready_for_dry_run"
      ).length,
      tone: "info" as const
    },
    {
      label: "Staging verification",
      value: items.filter(
        (item) => item.status.startsWith("staging_canary") || item.status === "staged_ready"
      ).length,
      tone: "good" as const
    },
    {
      label: "Consumer inbox delivery",
      value: items.filter(
        (item) =>
          item.status.startsWith("production_package") || item.status === "production_ready"
      ).length,
      tone: "info" as const
    },
    {
      label: "Consumer apply",
      value: items.filter(
        (item) => item.status.startsWith("consumer_") || item.status === "applied"
      ).length,
      tone: "watch" as const
    },
    {
      label: "Exceptions",
      value: items.filter((item) => queueStatusTones[item.status] === "danger").length,
      tone: "danger" as const
    }
  ];
  const max = Math.max(1, ...slices.map((slice) => slice.value));
  return slices.map((slice) => ({
    ...slice,
    percent: percentOf(slice.value, max)
  }));
}

export function percentOf(value: number, total: number): number {
  if (total <= 0) {
    return 0;
  }
  return Math.max(0, Math.min(100, Math.round((value / total) * 100)));
}

export function friendlyGeo(value: string): string {
  return value
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

export function friendlyCategory(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (normalized === "poi") {
    return "POI";
  }
  return friendlyGeo(normalized);
}

export function friendlyUnit(value: string): string {
  const [, geography, category] = value.split(":");
  if (!geography || !category) {
    return value;
  }
  return `${friendlyGeo(geography)} · ${friendlyCategory(category)}`;
}

export interface PlaceTypePresentation {
  primary: string;
  secondary: string;
  targetType: string;
}

export function describePlaceType(category: string): PlaceTypePresentation {
  const normalized = category.trim().toLowerCase();
  const targetFeatureType = mapVamoSourceCategoryToFeatureType(normalized);
  const sourceCategory = friendlyCategory(normalized);

  if (targetFeatureType === "landmark") {
    return {
      primary: "Landmark",
      secondary: "Source category: Landmark",
      targetType: "Landmark"
    };
  }

  if (targetFeatureType === "poi") {
    return {
      primary: "POI",
      secondary: normalized === "poi" ? "Source category: General" : `Source category: ${sourceCategory}`,
      targetType: "POI"
    };
  }

  return {
    primary: sourceCategory,
    secondary: "Source category not supported by this target",
    targetType: "Unsupported"
  };
}

export function progressiveSourceLabel(source: "live" | "sample" | "error"): string {
  if (source === "live") {
    return "Live control plane";
  }
  if (source === "error") {
    return "Live read failed · sample fallback";
  }
  return "Sample preview";
}

export function batchQueueSourceLabel(source: "live" | "sample" | "error"): string {
  if (source === "live") {
    return "Live control plane";
  }
  if (source === "error") {
    return "Live read failed · sample fallback";
  }
  return "Sample preview · planning-only queue";
}

export function autonomySourceLabel(source: "live" | "sample" | "error"): string {
  if (source === "live") {
    return "Live control plane";
  }
  if (source === "error") {
    return "Live read failed · sample fallback";
  }
  return "Sample preview · foundation only";
}

export function formatAgentAction(action: string): string {
  return action
    .replace(/schedule_dry_run/g, "schedule simulation")
    .replace(/execute_dry_run/g, "run simulation")
    .replace(/dry_run/g, "simulation")
    .replace(/staging_wave/g, "staging batch")
    .replace(/_/g, " ");
}

export type StagingApprovalQueueFilter =
  | "all"
  | "ready_for_dry_run"
  | "dry_run_passed"
  | "eligible_for_staging"
  | "staging_verified"
  | "ready_for_production"
  | "delivered"
  | "applied"
  | "blocked";

export const stagingApprovalQueueFilterLabels: Record<StagingApprovalQueueFilter, string> = {
  all: "All",
  ready_for_dry_run: "Ready to simulate",
  dry_run_passed: "Simulation passed",
  eligible_for_staging: "Eligible for staging",
  staging_verified: "Staging verified",
  ready_for_production: "Ready for production",
  delivered: "Delivered",
  applied: "Applied",
  blocked: "Blocked"
};

export function matchesStagingApprovalQueueFilter(
  status: BatchQueueItemStatus,
  filter: StagingApprovalQueueFilter,
  eligibleForStaging: boolean
): boolean {
  if (filter === "all") {
    return true;
  }
  switch (filter) {
    case "ready_for_dry_run":
      return status === "ready_for_dry_run" || status === "dry_run_ready" || status === "dry_run_running";
    case "dry_run_passed":
      return status === "dry_run_succeeded";
    case "eligible_for_staging":
      return eligibleForStaging;
    case "staging_verified":
      return status === "staging_canary_succeeded" || status === "staged_ready";
    case "ready_for_production":
      return (
        status === "production_ready" ||
        status === "production_package_ready" ||
        status === "staging_canary_succeeded" ||
        status === "staged_ready"
      );
    case "delivered":
      return (
        status === "production_package_delivered" ||
        status === "consumer_apply_pending" ||
        status === "production_package_delivering"
      );
    case "applied":
      return status === "consumer_applied" || status === "applied";
    case "blocked":
      return status === "blocked" || status.endsWith("_blocked");
    default:
      return true;
  }
}

export function describeStagingQueueEvidenceStatus(item: BatchQueueItem): string {
  if (item.status !== "dry_run_succeeded" && !item.dryRunReport) {
    return "No simulation evidence";
  }
  if (!item.dryRunReport) {
    return "Report missing";
  }
  if (item.dryRunReport.wroteToTarget !== false) {
    return "Invalid simulation invariant";
  }
  return "Simulation valid";
}

export function describeStagingQueueNextAction(item: BatchQueueItem, eligibleForStaging: boolean): string {
  if (item.blockReasons.length > 0 || item.status.endsWith("_blocked") || item.status === "blocked") {
    return "Investigate blockers";
  }
  if (eligibleForStaging) {
    return "Select for staging verification";
  }
  if (item.status === "dry_run_succeeded" && !isVamoStagingTargetCategoryCompatible(item.category)) {
    return describeVamoStagingTargetCategoryCompatibility(item.category).detail;
  }
  if (item.status === "dry_run_succeeded") {
    return "Simulation evidence invalid";
  }
  if (item.status === "staging_canary_ready" || item.status === "staging_canary_approved") {
    return "Await staging execution";
  }
  if (item.status === "staging_canary_running") {
    return "Staging write in progress";
  }
  if (item.status === "staging_canary_succeeded" || item.status === "staged_ready") {
    return "Ready for production package path";
  }
  if (item.status === "production_package_delivered" || item.status === "consumer_apply_pending") {
    return "Await consumer apply";
  }
  if (item.status === "consumer_applied" || item.status === "applied") {
    return "Complete";
  }
  if (item.status === "ready_for_dry_run" || item.status === "dry_run_ready") {
    return "Run simulation";
  }
  return "Monitor queue progression";
}

export interface DryRunReportMetrics {
  sourceCandidates: number;
  expectedTargetWrites: number;
}

export function extractDryRunReportMetrics(
  report: BatchQueueItem["dryRunReport"]
): DryRunReportMetrics | null {
  if (!report || report.wroteToTarget !== false) {
    return null;
  }
  return {
    sourceCandidates: report.rowsProcessed,
    expectedTargetWrites: report.insertCount + report.updateCount
  };
}

export const VAMO_STAGING_NATIVE_TARGET_CATEGORIES = ["poi", "landmark"] as const;
export const VAMO_STAGING_POI_SUBTYPE_CATEGORIES = ["restaurant", "transport", "hotel"] as const;

export type VamoStagingTargetCategoryCompatibilityStatus = "compatible" | "mapped" | "blocked";

export interface VamoStagingTargetCategoryCompatibility {
  status: VamoStagingTargetCategoryCompatibilityStatus;
  label: string;
  detail: string;
  targetFeatureType?: "poi" | "landmark";
}

export function isVamoStagingTargetCategoryCompatible(category: string): boolean {
  return mapVamoSourceCategoryToFeatureType(category) !== null;
}

function mapVamoSourceCategoryToFeatureType(category: string): "poi" | "landmark" | null {
  const normalized = category.trim().toLowerCase();
  if (normalized === "landmark") {
    return "landmark";
  }
  if (
    normalized === "poi" ||
    (VAMO_STAGING_POI_SUBTYPE_CATEGORIES as readonly string[]).includes(normalized)
  ) {
    return "poi";
  }
  return null;
}

export function describeVamoStagingTargetCategoryCompatibility(
  category: string
): VamoStagingTargetCategoryCompatibility {
  const targetFeatureType = mapVamoSourceCategoryToFeatureType(category);
  if (targetFeatureType === "landmark") {
    return {
      status: "compatible",
      label: "Target type: Landmark",
      detail: "Writes to Vamo as target type Landmark.",
      targetFeatureType
    };
  }
  if (targetFeatureType === "poi") {
    const normalized = category.trim().toLowerCase();
    const isSubtype = normalized !== "poi";
    return {
      status: isSubtype ? "mapped" : "compatible",
      label: isSubtype ? "Maps to POI" : "Target type: POI",
      detail: isSubtype
        ? `${category} is a POI subtype; writes to Vamo as target type POI.`
        : "Writes to Vamo as target type POI.",
      targetFeatureType
    };
  }
  return {
    status: "blocked",
    label: "Blocked",
    detail: `${category} is not supported for Vamo staging target writes.`
  };
}

export function isStagingWaveSelectable(item: BatchQueueItem): boolean {
  if (item.status !== "dry_run_succeeded" || !item.dryRunReport) {
    return false;
  }
  if (!isVamoStagingTargetCategoryCompatible(item.category)) {
    return false;
  }
  const metrics = extractDryRunReportMetrics(item.dryRunReport);
  if (!metrics) {
    return false;
  }
  return metrics.expectedTargetWrites >= 1 && metrics.expectedTargetWrites <= 50;
}
