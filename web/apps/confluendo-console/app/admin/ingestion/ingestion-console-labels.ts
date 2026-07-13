import type { BatchQueueItem, BatchQueueItemStatus } from "@confluendo/ingestion-platform/core";
import {
  describeVamoStagingTargetCategoryCompatibility,
  isVamoStagingTargetCategoryCompatible
} from "@confluendo/ingestion-platform/core/vamo-place-intelligence-presentation";
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
  agent: "Automation",
  staging: "Verify",
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

export interface EffectiveQueueLifecyclePresentation {
  label: string;
  detail?: string;
  lifecycle: string;
  tone: OperatorTone;
  fromPreviousPlan: boolean;
}

export function describeEffectiveQueueLifecycle(
  item: BatchQueueItem
): EffectiveQueueLifecyclePresentation {
  const historical = item.crossPlanPackageLifecycle;
  if (!historical) {
    return {
      label: queueStatusLabels[item.status],
      lifecycle: lifecycleStage(item.status),
      tone: queueStatusTones[item.status],
      fromPreviousPlan: false
    };
  }

  const detail = `Previous plan: ${historical.planKey}`;
  switch (historical.status) {
    case "approved":
      return {
        label: "Delivery approved in a previous plan",
        detail,
        lifecycle: "Consumer inbox delivery",
        tone: "watch",
        fromPreviousPlan: true
      };
    case "delivering":
      return {
        label: "Delivery in progress in a previous plan",
        detail,
        lifecycle: "Consumer inbox delivery",
        tone: "info",
        fromPreviousPlan: true
      };
    case "delivered":
      return {
        label: "Delivered to inbox in a previous plan",
        detail,
        lifecycle: "Consumer inbox delivery",
        tone: "info",
        fromPreviousPlan: true
      };
    case "consumer_apply_pending":
      return {
        label: "Waiting for Vamo apply in a previous plan",
        detail,
        lifecycle: "Consumer apply",
        tone: "watch",
        fromPreviousPlan: true
      };
    case "consumer_apply_failed":
      return {
        label: "Vamo apply failed in a previous plan",
        detail,
        lifecycle: "Consumer apply",
        tone: "danger",
        fromPreviousPlan: true
      };
    case "consumer_applied":
      return {
        label: "Already applied in a previous plan",
        detail,
        lifecycle: "Consumer apply",
        tone: "good",
        fromPreviousPlan: true
      };
  }
}

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
    .replace(/approve_or_execute_staging_wave_later/g, "staging verification")
    .replace(/approve_staging_wave/g, "approve staging verification")
    .replace(/staging_canary/g, "staging verification")
    .replace(/approve_production_package_wave/g, "approve production delivery package")
    .replace(/deliver_production_package_wave/g, "deliver production delivery package")
    .replace(/apply_consumer_package/g, "apply to Vamo")
    .replace(/production_package/g, "production delivery package")
    .replace(/dry_run/g, "simulation")
    .replace(/staging_wave/g, "staging verification batch")
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

export type ProductionPackageApprovalQueueFilter =
  | "eligible_for_package"
  | "delivered_to_inbox"
  | "apply_pending"
  | "applied"
  | "blocked"
  | "all";

export const productionPackageApprovalQueueFilterLabels: Record<
  ProductionPackageApprovalQueueFilter,
  string
> = {
  eligible_for_package: "Eligible for package",
  delivered_to_inbox: "Delivered to inbox",
  apply_pending: "Apply pending",
  applied: "Applied",
  blocked: "Blocked",
  all: "All"
};

export function isProductionPackageWaveSelectable(
  item: BatchQueueItem,
  input?: { occupied?: boolean; stagingSucceeded?: boolean }
): boolean {
  if (item.crossPlanPackageLifecycle) {
    return false;
  }
  if (item.status !== "staging_canary_succeeded") {
    return false;
  }
  if (item.blockReasons.length > 0) {
    return false;
  }
  if (item.dryRunReport?.wroteToTarget !== false) {
    return false;
  }
  if (input?.occupied) {
    return false;
  }
  if (input?.stagingSucceeded === false) {
    return false;
  }
  const metrics = extractDryRunReportMetrics(item.dryRunReport);
  return Boolean(metrics && metrics.expectedTargetWrites > 0);
}

export function matchesProductionPackageApprovalQueueFilter(
  item: BatchQueueItem,
  filter: ProductionPackageApprovalQueueFilter,
  eligibleForPackage: boolean
): boolean {
  if (filter === "all") {
    return true;
  }
  switch (filter) {
    case "eligible_for_package":
      return eligibleForPackage;
    case "delivered_to_inbox":
      return (
        item.crossPlanPackageLifecycle?.status === "delivered" ||
        item.crossPlanPackageLifecycle?.status === "delivering" ||
        item.status === "production_package_delivered" ||
        item.status === "production_package_delivering" ||
        item.status === "consumer_apply_pending"
      );
    case "apply_pending":
      return (
        item.crossPlanPackageLifecycle?.status === "consumer_apply_pending" ||
        item.status === "consumer_apply_pending"
      );
    case "applied":
      return (
        item.crossPlanPackageLifecycle?.status === "consumer_applied" ||
        item.status === "consumer_applied" ||
        item.status === "applied"
      );
    case "blocked":
      return (
        item.crossPlanPackageLifecycle?.status === "consumer_apply_failed" ||
        item.status === "blocked" ||
        item.status.endsWith("_blocked")
      );
    default:
      return true;
  }
}

export function describeProductionPackageQueueStagingStatus(
  stagingSucceeded?: boolean
): string {
  if (stagingSucceeded === true) {
    return "Staging verified";
  }
  if (stagingSucceeded === false) {
    return "Staging evidence missing";
  }
  return "—";
}

export function describeProductionPackageQueueNextAction(
  item: BatchQueueItem,
  eligibleForPackage: boolean
): string {
  const historical = item.crossPlanPackageLifecycle;
  if (historical?.status === "consumer_applied") {
    return `Complete in ${historical.planKey}`;
  }
  if (historical?.status === "consumer_apply_failed") {
    return `Review failed apply in ${historical.planKey}`;
  }
  if (historical) {
    return `Follow ${historical.planKey} delivery`;
  }
  if (item.blockReasons.length > 0 || item.status.endsWith("_blocked") || item.status === "blocked") {
    return "Investigate blockers";
  }
  if (eligibleForPackage) {
    return "Select for package wave";
  }
  if (item.status === "production_package_approved") {
    return "Await delivery runbook";
  }
  if (item.status === "production_package_delivered" || item.status === "consumer_apply_pending") {
    return "Apply to Vamo";
  }
  if (item.status === "consumer_applied" || item.status === "applied") {
    return "Complete";
  }
  if (item.status === "staging_canary_succeeded") {
    return "Occupied or awaiting selection";
  }
  return "Not yet staging verified";
}
