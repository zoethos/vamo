/**
 * Selected scope workflow context (UX-2).
 *
 * Pure derivation from existing ingestion dashboard snapshot props. Never invents
 * evidence that is not present in the supplied batch queue or wave item records.
 */

import type {
  BatchQueueItem,
  BatchQueueItemStatus,
  BatchQueueLatestProductionPackageWaveItem,
  BatchQueueLatestWaveItem,
  BatchQueueSnapshot
} from "./batch-queue-read-model.js";
import {
  isActionableWorkflowAttentionItem,
  type WorkflowStageTone
} from "./workflow-navigator-presenter.js";

const PARKED_EMPTY_SOURCE_BLOCK_REASON = "source_snapshot_empty";

export type ScopeWorkflowDispositionKey =
  | "parked"
  | "blocked"
  | "awaiting_approval"
  | "in_progress"
  | "delivered"
  | "applied";

export interface ScopeWorkflowEvidenceEntry {
  kind: "simulation" | "staging_verification" | "delivery" | "consumer_apply";
  label: string;
  status: string;
  detail: string;
  available: boolean;
}

export interface ScopeWorkflowDisplayField {
  key: string;
  label: string;
  value: string;
  detail?: string;
}

export interface ScopeWorkflowContextPresentation {
  mode: "scope";
  title: string;
  friendlyName: string;
  unitKey: string;
  displayFields: ReadonlyArray<ScopeWorkflowDisplayField>;
  workflowStage: {
    label: string;
    summary: string;
    tone: WorkflowStageTone;
  };
  lifecycle: {
    label: string;
    detail?: string;
    tone: WorkflowStageTone;
  };
  disposition: {
    key: ScopeWorkflowDispositionKey;
    label: string;
    tone: WorkflowStageTone;
  };
  nextAction: string;
  sourceCandidates: string | null;
  expectedTargetWrites: string | null;
  evidenceTrail: ScopeWorkflowEvidenceEntry[];
  isParkedEmptySource: boolean;
  needsAttention: boolean;
}

export interface ScopeDeliveryWaveItemPresentation {
  unitKey: string;
  statusPresentation?: { label: string };
  consumerApplyStatus?: string | null;
  packageId?: string | null;
  contentEquivalenceLabel?: string;
  telemetrySource?: string;
}

export interface ScopeWorkflowPresenterInput {
  selectedUnitKey: string | null;
  batchQueue: BatchQueueSnapshot;
  stagingEvidenceByUnitKey?: Readonly<Record<string, { status?: string }>>;
  deliveryWaveItemsPresentation?: ReadonlyArray<ScopeDeliveryWaveItemPresentation> | null;
}

const UNAVAILABLE = "Unavailable — no record for this scope.";

export function presentScopeWorkflowContext(
  input: ScopeWorkflowPresenterInput
): ScopeWorkflowContextPresentation | null {
  if (!input.selectedUnitKey) {
    return null;
  }

  const item = input.batchQueue.items.find((entry) => entry.unitKey === input.selectedUnitKey);
  if (!item) {
    return null;
  }

  const stagingWaveItem = findStagingWaveItem(input.batchQueue, input.selectedUnitKey);
  const deliveryWaveItem = findDeliveryWaveItem(input.batchQueue, input.selectedUnitKey);
  const deliveryPresentation = findDeliveryPresentation(
    input.deliveryWaveItemsPresentation,
    input.selectedUnitKey,
    deliveryWaveItem
  );
  const stagingEvidence = input.stagingEvidenceByUnitKey?.[input.selectedUnitKey];

  const isParkedEmptySource = isParkedEmptySourceScope(item);
  const lifecycle = describeScopeLifecycle(item);
  const disposition = describeScopeDisposition(item, isParkedEmptySource, deliveryWaveItem);
  const workflowStage = describeScopeWorkflowStage(item, isParkedEmptySource);
  const metrics = extractDryRunMetrics(item.dryRunReport);
  const evidenceTrail = buildEvidenceTrail({
    item,
    stagingWaveItem,
    deliveryWaveItem,
    deliveryPresentation,
    stagingEvidence
  });

  return {
    mode: "scope",
    title: "Scope context",
    friendlyName: friendlyUnitKey(item.unitKey),
    unitKey: item.unitKey,
    displayFields: item.displayFields ?? [],
    workflowStage,
    lifecycle,
    disposition,
    nextAction: describeScopeNextAction(item, isParkedEmptySource, deliveryWaveItem, stagingWaveItem),
    sourceCandidates: metrics ? String(metrics.sourceCandidates) : null,
    expectedTargetWrites: metrics ? String(metrics.expectedTargetWrites) : null,
    evidenceTrail,
    isParkedEmptySource,
    needsAttention: isActionableWorkflowAttentionItem(item)
  };
}

function findStagingWaveItem(
  batchQueue: BatchQueueSnapshot,
  unitKey: string
): BatchQueueLatestWaveItem | undefined {
  return batchQueue.latestWave?.items?.find((entry) => entry.unitKey === unitKey);
}

function findDeliveryWaveItem(
  batchQueue: BatchQueueSnapshot,
  unitKey: string
): BatchQueueLatestProductionPackageWaveItem | undefined {
  return batchQueue.latestProductionPackageWave?.items?.find((entry) => entry.unitKey === unitKey);
}

function findDeliveryPresentation(
  items: ScopeWorkflowPresenterInput["deliveryWaveItemsPresentation"],
  unitKey: string,
  deliveryWaveItem: BatchQueueLatestProductionPackageWaveItem | undefined
): ScopeDeliveryWaveItemPresentation | undefined {
  if (!deliveryWaveItem) {
    return undefined;
  }
  return items?.find((entry) => entry.unitKey === unitKey);
}

function isParkedEmptySourceScope(item: BatchQueueItem): boolean {
  return (
    item.status === "blocked" &&
    item.blockReasons.length > 0 &&
    item.blockReasons.every((reason) => reason === PARKED_EMPTY_SOURCE_BLOCK_REASON)
  );
}

function friendlyUnitKey(unitKey: string): string {
  const parts = unitKey.split(":");
  if (parts.length >= 3) {
    const geography = parts[1]?.replace(/-/g, " ") ?? parts[1];
    const category = parts[2]?.replace(/-/g, " ") ?? parts[2];
    if (geography && category) {
      return `${titleCase(geography)} · ${titleCase(category)}`;
    }
  }
  return unitKey;
}

function titleCase(value: string): string {
  return value
    .split(/\s+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function extractDryRunMetrics(
  report: BatchQueueItem["dryRunReport"]
): { sourceCandidates: number; expectedTargetWrites: number } | null {
  if (!report || report.wroteToTarget !== false) {
    return null;
  }
  return {
    sourceCandidates: report.rowsProcessed,
    expectedTargetWrites: report.insertCount + report.updateCount
  };
}

function describeScopeLifecycle(item: BatchQueueItem): ScopeWorkflowContextPresentation["lifecycle"] {
  const historical = item.crossPlanPackageLifecycle;
  if (historical) {
    return {
      label: humanizeStatus(historical.status),
      detail: `Previous plan: ${historical.planKey}`,
      tone: lifecycleToneForHistorical(historical.status)
    };
  }

  return {
    label: humanizeStatus(item.status),
    detail: item.blockReasons.length > 0 ? item.blockReasons.map(humanizeBlocker).join("; ") : undefined,
    tone: lifecycleToneForStatus(item.status, item.blockReasons.length > 0)
  };
}

function describeScopeDisposition(
  item: BatchQueueItem,
  isParkedEmptySource: boolean,
  deliveryWaveItem: BatchQueueLatestProductionPackageWaveItem | undefined
): ScopeWorkflowContextPresentation["disposition"] {
  if (isParkedEmptySource) {
    return { key: "parked", label: "Parked", tone: "neutral" };
  }

  if (
    item.status === "consumer_applied" ||
    item.crossPlanPackageLifecycle?.status === "consumer_applied" ||
    deliveryWaveItem?.consumerApplyStatus === "applied"
  ) {
    return { key: "applied", label: "Applied by consumer", tone: "good" };
  }

  if (deliveryWaveItem?.consumerApplyStatus === "failed") {
    return { key: "blocked", label: "Consumer apply failed", tone: "danger" };
  }

  if (
    item.status === "production_package_delivered" ||
    item.status === "consumer_apply_pending" ||
    deliveryWaveItem?.status === "delivered" ||
    deliveryWaveItem?.status === "production_package_delivered" ||
    deliveryWaveItem?.consumerApplyStatus === "pending"
  ) {
    return { key: "delivered", label: "Delivered to consumer inbox", tone: "good" };
  }

  if (
    item.status.endsWith("_blocked") ||
    (item.status === "blocked" && item.blockReasons.length > 0)
  ) {
    return { key: "blocked", label: "Blocked", tone: "danger" };
  }

  if (
    item.status === "staging_canary_ready" ||
    item.status === "staging_canary_approved" ||
    item.status === "production_package_ready" ||
    item.status === "production_package_approved"
  ) {
    return { key: "awaiting_approval", label: "Awaiting approval", tone: "watch" };
  }

  if (
    item.status.endsWith("_running") ||
    item.status === "production_package_delivering" ||
    item.status === "dry_run_running"
  ) {
    return { key: "in_progress", label: "In progress", tone: "info" };
  }

  return { key: "in_progress", label: "In pipeline", tone: "neutral" };
}

function describeScopeWorkflowStage(
  item: BatchQueueItem,
  isParkedEmptySource: boolean
): ScopeWorkflowContextPresentation["workflowStage"] {
  if (isParkedEmptySource) {
    return {
      label: "Queue",
      summary: "Parked until source snapshot coverage expands.",
      tone: "neutral"
    };
  }

  const stage = workflowStageForStatus(item.status);
  return {
    label: stage.label,
    summary: stage.summary,
    tone: stage.tone
  };
}

function workflowStageForStatus(status: BatchQueueItemStatus): {
  label: string;
  summary: string;
  tone: WorkflowStageTone;
} {
  switch (status) {
    case "planned":
    case "ready_for_dry_run":
    case "blocked":
      return {
        label: "Queue",
        summary: "Waiting in the batch queue before simulation.",
        tone: "neutral"
      };
    case "dry_run_ready":
    case "dry_run_running":
    case "dry_run_succeeded":
    case "dry_run_blocked":
      return {
        label: "Simulate",
        summary: "Simulation evidence stage.",
        tone: status === "dry_run_blocked" ? "danger" : "info"
      };
    case "staging_canary_ready":
    case "staging_canary_approved":
    case "staging_canary_running":
    case "staging_canary_succeeded":
    case "staging_canary_blocked":
    case "staged_ready":
      return {
        label: "Verify staging",
        summary: "Staging verification against the consumer-shaped target.",
        tone: status === "staging_canary_blocked" ? "danger" : "info"
      };
    case "production_ready":
    case "production_package_ready":
    case "production_package_approved":
    case "production_package_delivering":
    case "production_package_delivered":
    case "production_package_blocked":
    case "consumer_apply_pending":
    case "consumer_apply_failed":
      return {
        label: "Delivery",
        summary: "Consumer inbox delivery and apply handoff.",
        tone: status === "production_package_blocked" || status === "consumer_apply_failed" ? "danger" : "info"
      };
    case "consumer_applied":
    case "applied":
      return {
        label: "Consumer apply",
        summary: "Consumer confirmed product apply.",
        tone: "good"
      };
    default:
      return {
        label: "Pipeline",
        summary: humanizeStatus(status),
        tone: "neutral"
      };
  }
}

function describeScopeNextAction(
  item: BatchQueueItem,
  isParkedEmptySource: boolean,
  deliveryWaveItem: BatchQueueLatestProductionPackageWaveItem | undefined,
  stagingWaveItem: BatchQueueLatestWaveItem | undefined
): string {
  if (isParkedEmptySource) {
    return "Parked until source snapshot coverage expands — no operator remediation required.";
  }

  const historical = item.crossPlanPackageLifecycle;
  if (historical?.status === "consumer_applied") {
    return `Complete in previous plan ${historical.planKey}.`;
  }
  if (historical?.status === "consumer_apply_failed") {
    return `Review failed consumer apply in previous plan ${historical.planKey}.`;
  }
  if (historical) {
    return `Follow delivery evidence in previous plan ${historical.planKey}.`;
  }

  if (deliveryWaveItem?.consumerApplyStatus === "applied") {
    return "No further ingestion action — consumer apply is complete.";
  }
  if (deliveryWaveItem?.consumerApplyStatus === "failed") {
    return "Review consumer apply failure evidence with the product team.";
  }

  if (item.blockReasons.length > 0 || item.status.endsWith("_blocked") || item.status === "blocked") {
    return "Investigate blockers before advancing this scope.";
  }

  switch (item.status) {
    case "planned":
    case "ready_for_dry_run":
      return "Review queue readiness and schedule simulation when eligible.";
    case "dry_run_ready":
      return "Wait for the next bounded simulation execution.";
    case "dry_run_running":
      return "Wait for simulation to finish.";
    case "dry_run_succeeded":
      return stagingWaveItem
        ? "Review staging verification evidence from the latest batch."
        : "Select for staging verification when simulation evidence is valid.";
    case "staging_canary_ready":
    case "staging_canary_approved":
      return "Approve or execute staging verification for this scope.";
    case "staging_canary_running":
      return "Wait for staging verification to finish.";
    case "staging_canary_succeeded":
    case "staged_ready":
    case "production_ready":
      return "Select for consumer inbox delivery packaging when eligible.";
    case "production_package_ready":
    case "production_package_approved":
      return "Approve or execute delivery for this scope.";
    case "production_package_delivering":
      return "Wait for delivery to finish.";
    case "production_package_delivered":
    case "consumer_apply_pending":
      return deliveryWaveItem?.consumerApplyStatus === "pending"
        ? "Consumer apply is pending in the product workspace."
        : "Confirm consumer inbox delivery, then apply in the consumer product when ready.";
    case "consumer_applied":
    case "applied":
      return "No further ingestion action — consumer apply is complete.";
    case "consumer_apply_failed":
      return "Review consumer apply failure evidence with the product team.";
    default:
      return "Review the latest ledger evidence for this scope.";
  }
}

function buildEvidenceTrail(input: {
  item: BatchQueueItem;
  stagingWaveItem?: BatchQueueLatestWaveItem;
  deliveryWaveItem?: BatchQueueLatestProductionPackageWaveItem;
  deliveryPresentation?: ScopeDeliveryWaveItemPresentation;
  stagingEvidence?: { status?: string };
}): ScopeWorkflowEvidenceEntry[] {
  return [
    presentSimulationEvidence(input.item),
    presentStagingEvidence(input.item, input.stagingWaveItem, input.stagingEvidence),
    presentDeliveryEvidence(input.deliveryWaveItem, input.deliveryPresentation),
    presentConsumerApplyEvidence(input.item, input.deliveryWaveItem, input.deliveryPresentation)
  ];
}

function presentSimulationEvidence(item: BatchQueueItem): ScopeWorkflowEvidenceEntry {
  if (!item.dryRunReport) {
    return {
      kind: "simulation",
      label: "Simulation",
      status: "No record",
      detail: UNAVAILABLE,
      available: false
    };
  }

  const metrics = extractDryRunMetrics(item.dryRunReport);
  return {
    kind: "simulation",
    label: "Simulation",
    status: humanizeStatus(item.status.startsWith("dry_run") ? item.status : "dry_run_succeeded"),
    detail: metrics
      ? `${metrics.sourceCandidates} source candidates · ${metrics.expectedTargetWrites} expected target writes · no target write`
      : `${item.dryRunReport.rowsProcessed} rows processed`,
    available: true
  };
}

function presentStagingEvidence(
  item: BatchQueueItem,
  stagingWaveItem: BatchQueueLatestWaveItem | undefined,
  stagingEvidence: { status?: string } | undefined
): ScopeWorkflowEvidenceEntry {
  if (stagingWaveItem) {
    return {
      kind: "staging_verification",
      label: "Staging verification",
      status: humanizeStatus(stagingWaveItem.status),
      detail: [
        stagingWaveItem.plannedRowCount
          ? `${stagingWaveItem.plannedRowCount} expected target writes`
          : null,
        stagingWaveItem.shipmentId ? `Shipment ${stagingWaveItem.shipmentId}` : null,
        stagingWaveItem.blockers.length > 0 ? stagingWaveItem.blockers.join("; ") : null
      ]
        .filter(Boolean)
        .join(" · ") || "Recorded in latest staging verification batch.",
      available: true
    };
  }

  if (item.status.startsWith("staging_canary") || item.status === "staged_ready") {
    return {
      kind: "staging_verification",
      label: "Staging verification",
      status: humanizeStatus(item.status),
      detail: stagingEvidence?.status
        ? `Ledger status: ${humanizeStatus(stagingEvidence.status)}`
        : "Scope status indicates staging verification activity, but no matching latest-batch row.",
      available: Boolean(stagingEvidence?.status)
    };
  }

  if (stagingEvidence?.status) {
    return {
      kind: "staging_verification",
      label: "Staging verification",
      status: humanizeStatus(stagingEvidence.status),
      detail: "Derived staging evidence only — not present in the latest staging verification batch.",
      available: true
    };
  }

  return {
    kind: "staging_verification",
    label: "Staging verification",
    status: "No record",
    detail: UNAVAILABLE,
    available: false
  };
}

function presentDeliveryEvidence(
  deliveryWaveItem: BatchQueueLatestProductionPackageWaveItem | undefined,
  deliveryPresentation: ScopeDeliveryWaveItemPresentation | undefined
): ScopeWorkflowEvidenceEntry {
  if (!deliveryWaveItem) {
    return {
      kind: "delivery",
      label: "Consumer inbox delivery",
      status: "No record",
      detail: UNAVAILABLE,
      available: false
    };
  }

  const status =
    deliveryPresentation?.statusPresentation?.label ?? humanizeStatus(deliveryWaveItem.status);
  const packageId = deliveryPresentation?.packageId ?? deliveryWaveItem.packageId;
  const content = deliveryPresentation?.contentEquivalenceLabel ?? deliveryWaveItem.contentEquivalenceLabel;

  return {
    kind: "delivery",
    label: "Consumer inbox delivery",
    status,
    detail: [
      packageId ? `Package ${packageId}` : null,
      content ? `Content ${content}` : null,
      deliveryWaveItem.plannedRowCount
        ? `${deliveryWaveItem.plannedRowCount} planned rows`
        : null,
      deliveryPresentation?.telemetrySource === "missing" ||
      deliveryWaveItem.telemetrySource === "missing"
        ? "Telemetry missing"
        : null
    ]
      .filter(Boolean)
      .join(" · ") || "Recorded in latest delivery batch.",
    available: true
  };
}

function presentConsumerApplyEvidence(
  item: BatchQueueItem,
  deliveryWaveItem: BatchQueueLatestProductionPackageWaveItem | undefined,
  deliveryPresentation: ScopeDeliveryWaveItemPresentation | undefined
): ScopeWorkflowEvidenceEntry {
  const applyStatus =
    deliveryPresentation?.consumerApplyStatus ??
    deliveryWaveItem?.consumerApplyStatus ??
    (item.status === "consumer_applied"
      ? "applied"
      : item.status === "consumer_apply_failed"
        ? "failed"
        : item.status === "consumer_apply_pending"
          ? "pending"
          : null);

  if (!applyStatus) {
    return {
      kind: "consumer_apply",
      label: "Consumer apply",
      status: "No record",
      detail: UNAVAILABLE,
      available: false
    };
  }

  return {
    kind: "consumer_apply",
    label: "Consumer apply",
    status: humanizeApplyStatus(applyStatus),
    detail:
      applyStatus === "pending"
        ? "Consumer product apply is pending."
        : applyStatus === "applied"
          ? "Consumer confirmed product apply."
          : applyStatus === "failed"
            ? "Consumer apply failed — review with the product team."
            : humanizeApplyStatus(applyStatus),
    available: true
  };
}

function humanizeApplyStatus(status: string): string {
  switch (status) {
    case "pending":
      return "Pending";
    case "applied":
      return "Applied";
    case "failed":
      return "Failed";
    default:
      return humanizeStatus(status);
  }
}

function humanizeStatus(status: string): string {
  return sanitizeOperatorCopy(status.replace(/_/g, " "));
}

function humanizeBlocker(reason: string): string {
  if (reason === PARKED_EMPTY_SOURCE_BLOCK_REASON) {
    return "source snapshot empty";
  }
  return reason.replace(/_/g, " ");
}

function lifecycleToneForStatus(status: BatchQueueItemStatus, hasBlockers: boolean): WorkflowStageTone {
  if (hasBlockers || status.endsWith("_blocked") || status === "consumer_apply_failed") {
    return "danger";
  }
  if (status === "consumer_applied" || status === "applied") {
    return "good";
  }
  if (status.endsWith("_ready") || status.endsWith("_approved") || status === "consumer_apply_pending") {
    return "watch";
  }
  if (status.endsWith("_running") || status.endsWith("_delivering")) {
    return "info";
  }
  return "neutral";
}

function lifecycleToneForHistorical(status: string): WorkflowStageTone {
  switch (status) {
    case "consumer_applied":
      return "good";
    case "consumer_apply_failed":
    case "blocked":
      return "danger";
    case "consumer_apply_pending":
    case "delivered":
    case "delivering":
      return "watch";
    default:
      return "neutral";
  }
}

function sanitizeOperatorCopy(value: string): string {
  return value
    .replace(/staging_canary/gi, "staging verification")
    .replace(/\bcanary\b/gi, "staging verification")
    .replace(/dry_run/gi, "simulation")
    .replace(/production_package/gi, "delivery package")
    .replace(/run_key/gi, "run reference")
    .trim();
}
