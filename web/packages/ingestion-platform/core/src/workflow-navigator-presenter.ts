/**
 * Workflow navigator presentation (UX-1).
 *
 * Pure derivation from existing ingestion dashboard inputs. Never invents
 * snapshot/release state that is not present in the supplied props.
 */

import type { BatchQueueItem, BatchQueueSnapshot } from "./batch-queue-read-model.js";

export type WorkflowConsoleView =
  | "overview"
  | "queue"
  | "agent"
  | "staging"
  | "delivery"
  | "diagnostics";

export type WorkflowNavigatorStageKey =
  | "source_release"
  | "queue_ready"
  | "simulate"
  | "verify_staging"
  | "prepare_delivery"
  | "apply_vamo"
  | "needs_attention";

export type WorkflowStageTone = "good" | "watch" | "danger" | "neutral" | "info";

export type WorkflowStageNavigation =
  | { kind: "view"; view: WorkflowConsoleView }
  | { kind: "href"; href: string };

export interface WorkflowNavigatorMetric {
  label: string;
  value: number;
}

export interface WorkflowNavigatorStagePresentation {
  key: WorkflowNavigatorStageKey;
  label: string;
  tone: WorkflowStageTone;
  summary: string;
  metrics: WorkflowNavigatorMetric[];
  navigation: WorkflowStageNavigation;
  actionNeeded: boolean;
}

export interface WorkflowNavigatorPresentation {
  mode: "portfolio";
  title: string;
  attentionCount: number;
  attentionSummary: string | null;
  stages: WorkflowNavigatorStagePresentation[];
  attentionStage: WorkflowNavigatorStagePresentation;
  ownershipNote: string;
}

export interface WorkflowDecisionHeaderPresentation {
  kicker: string;
  state: string;
  purpose: string;
  nextAction: string;
  helpSectionLabel: string;
  tone: WorkflowStageTone;
}

export interface RegisteredSnapshotReleaseSummary {
  releaseId: string;
  status: "activation_ready" | "activated";
}

export interface WorkflowNavigatorPresenterInput {
  batchQueue: BatchQueueSnapshot;
  batchQueueEligibleCount: number;
  batchCanaryWaveEligibleCount: number;
  productionPackageEligibleCount: number;
  attentionRows: readonly BatchQueueItem[];
  operatorNextAction: string;
  registeredSnapshotRelease?: RegisteredSnapshotReleaseSummary | null;
  latestWaveScopeCount?: number;
  expectedDeliveryWrites?: number;
  activeView: WorkflowConsoleView;
}

const OWNERSHIP_NOTE =
  "Confluendo owns ingestion control and delivery to the consumer inbox. Applying into product tables stays on the consumer side.";
const PARKED_EMPTY_SOURCE_BLOCK_REASON = "source_snapshot_empty";

// Extend input with optional source label for decision header only.
export interface WorkflowDecisionPresenterInput extends WorkflowNavigatorPresenterInput {
  batchQueueSourceLabel?: string;
}

export function presentWorkflowDecisionHeader(
  input: WorkflowDecisionPresenterInput
): WorkflowDecisionHeaderPresentation {
  const navigator = presentWorkflowNavigator(input);
  const stageForView = stageKeyForView(input.activeView);
  const stage =
    (stageForView === "needs_attention" ? navigator.attentionStage : undefined) ??
    navigator.stages.find((entry) => entry.key === stageForView) ??
    navigator.stages.find((entry) => entry.key === "queue_ready")!;

  const helpSectionLabel = helpLabelForView(input.activeView);

  return {
    kicker: viewKicker(input.activeView),
    state: stage.summary,
    purpose: viewPurpose(input.activeView, input.batchQueueSourceLabel),
    nextAction: sanitizeOperatorCopy(input.operatorNextAction || stage.summary),
    helpSectionLabel,
    tone: stage.tone
  };
}

export function presentWorkflowNavigator(
  input: WorkflowNavigatorPresenterInput
): WorkflowNavigatorPresentation {
  const progress = input.batchQueue.progress;
  const parkedEmptySourceCount = input.batchQueue.items.filter(
    (item) => !isActionableWorkflowAttentionItem(item)
  ).length;
  const actionableAttentionRows = input.attentionRows.filter(isActionableWorkflowAttentionItem);
  const attentionCount = actionableAttentionRows.length;
  const attentionStage = presentNeedsAttentionStage(
    attentionCount,
    input.batchQueue.blockerSummaries.filter(
      (blocker) => blocker.reason !== PARKED_EMPTY_SOURCE_BLOCK_REASON
    )
  );
  const stages: WorkflowNavigatorStagePresentation[] = [
    presentSourceReleaseStage(input.registeredSnapshotRelease),
    presentQueueReadyStage(progress, input.batchQueueEligibleCount, parkedEmptySourceCount),
    presentSimulateStage(progress),
    presentVerifyStagingStage(progress, input.batchCanaryWaveEligibleCount),
    presentPrepareDeliveryStage(
      input.productionPackageEligibleCount,
      progress.productionPackage,
      input.batchQueue.latestProductionPackageWave,
      input.latestWaveScopeCount,
      input.expectedDeliveryWrites
    ),
    presentApplyVamoStage(progress.productionPackage)
  ];

  return {
    mode: "portfolio",
    title: "Portfolio workflow",
    attentionCount,
    attentionSummary:
      attentionCount > 0
        ? `${attentionCount} scope${attentionCount === 1 ? "" : "s"} need operator review before automation can advance them.`
        : null,
    stages,
    attentionStage,
    ownershipNote: OWNERSHIP_NOTE
  };
}

export function isActionableWorkflowAttentionItem(item: BatchQueueItem): boolean {
  return !(
    item.status === "blocked" &&
    item.blockReasons.length > 0 &&
    item.blockReasons.every((reason) => reason === PARKED_EMPTY_SOURCE_BLOCK_REASON)
  );
}

function presentSourceReleaseStage(
  release?: RegisteredSnapshotReleaseSummary | null
): WorkflowNavigatorStagePresentation {
  const connected =
    release?.status === "activation_ready" || release?.status === "activated";
  return {
    key: "source_release",
    label: "Source release",
    tone: connected ? "good" : "neutral",
    summary: connected
      ? `Registered release ${release!.releaseId} is ready for downstream binding.`
      : "Not connected — no registered snapshot release is available in this view yet.",
    metrics: connected
      ? [{ label: "Registered", value: 1 }]
      : [{ label: "Connected", value: 0 }],
    navigation: { kind: "href", href: "/admin/providers" },
    actionNeeded: false
  };
}

function presentQueueReadyStage(
  progress: BatchQueueSnapshot["progress"],
  eligibleCount: number,
  parkedEmptySourceCount: number
): WorkflowNavigatorStagePresentation {
  const ready = progress.ready;
  const actionableBlocked = Math.max(progress.blocked - parkedEmptySourceCount, 0);
  return {
    key: "queue_ready",
    label: "Queue ready",
    tone: actionableBlocked > 0 ? "watch" : ready > 0 ? "info" : "neutral",
    summary:
      actionableBlocked > 0
        ? `${actionableBlocked} scope${actionableBlocked === 1 ? "" : "s"} need review before simulation can start.`
        : ready > 0
          ? `${ready} scope${ready === 1 ? "" : "s"} ready for the next bounded step.`
          : parkedEmptySourceCount > 0
            ? `${parkedEmptySourceCount} source scope${parkedEmptySourceCount === 1 ? "" : "s"} parked until snapshot coverage expands.`
          : "Queue is waiting for new supply-ready scopes.",
    metrics: [
      { label: "Ready", value: ready },
      { label: "Planned", value: progress.planned },
      { label: "Parked", value: parkedEmptySourceCount },
      { label: "Needs review", value: actionableBlocked }
    ],
    navigation: { kind: "view", view: "queue" },
    actionNeeded: actionableBlocked > 0 || eligibleCount > 0
  };
}

function presentSimulateStage(
  progress: BatchQueueSnapshot["progress"]
): WorkflowNavigatorStagePresentation {
  const ready = progress.execution.dryRunReady;
  const running = progress.execution.dryRunRunning;
  const passed = progress.execution.dryRunSucceeded;
  const blocked = progress.execution.dryRunBlocked;
  return {
    key: "simulate",
    label: "Simulate",
    tone: blocked > 0 ? "danger" : running > 0 ? "info" : passed > 0 ? "good" : ready > 0 ? "info" : "neutral",
    summary:
      blocked > 0
        ? `${blocked} simulation scope${blocked === 1 ? "" : "s"} blocked and need review.`
        : running > 0
          ? `${running} simulation scope${running === 1 ? " is" : "s are"} running.`
        : passed > 0
          ? `${passed} scope${passed === 1 ? "" : "s"} passed simulation with safe evidence.`
          : ready > 0
            ? `${ready} scope${ready === 1 ? "" : "s"} waiting to simulate.`
            : "No scopes are queued for simulation.",
    metrics: [
      { label: "Ready", value: ready },
      { label: "Running", value: running },
      { label: "Passed", value: passed },
      { label: "Blocked", value: blocked }
    ],
    navigation: { kind: "view", view: "agent" },
    actionNeeded: blocked > 0 || ready > 0 || running > 0
  };
}

function presentVerifyStagingStage(
  progress: BatchQueueSnapshot["progress"],
  eligibleCount: number
): WorkflowNavigatorStagePresentation {
  const eligible = eligibleCount;
  const verified = progress.stagingCanary.succeeded;
  const blocked = progress.stagingCanary.blocked;
  return {
    key: "verify_staging",
    label: "Verify in staging",
    tone: blocked > 0 ? "danger" : verified > 0 ? "good" : eligible > 0 ? "watch" : "neutral",
    summary:
      blocked > 0
        ? `${blocked} scope${blocked === 1 ? "" : "s"} failed staging verification.`
        : verified > 0
          ? `${verified} scope${verified === 1 ? "" : "s"} verified in staging.`
          : eligible > 0
            ? `${eligible} scope${eligible === 1 ? "" : "s"} eligible for staging verification.`
            : "No scopes are waiting for staging verification.",
    metrics: [
      { label: "Eligible", value: eligible },
      { label: "Verified", value: verified },
      { label: "Blocked", value: blocked }
    ],
    navigation: { kind: "view", view: "staging" },
    actionNeeded: blocked > 0 || eligible > 0
  };
}

function presentPrepareDeliveryStage(
  eligibleCount: number,
  productionPackage: BatchQueueSnapshot["progress"]["productionPackage"],
  latestWave: BatchQueueSnapshot["latestProductionPackageWave"],
  waveScopeCount?: number,
  expectedWrites?: number
): WorkflowNavigatorStagePresentation {
  const inFlight =
    productionPackage.approved +
    productionPackage.delivering +
    productionPackage.delivered +
    productionPackage.applyPending;
  const hasActiveDelivery = inFlight > 0;
  const scopeCount = hasActiveDelivery ? waveScopeCount ?? latestWave?.items?.length ?? 0 : 0;
  const writes = hasActiveDelivery
    ? expectedWrites ?? sumPlannedRows(latestWave?.items)
    : 0;
  const blocked = productionPackage.blocked;
  return {
    key: "prepare_delivery",
    label: "Prepare delivery",
    tone: blocked > 0 ? "danger" : eligibleCount > 0 ? "watch" : hasActiveDelivery ? "info" : "neutral",
    summary:
      blocked > 0
        ? `${blocked} delivery package${blocked === 1 ? " is" : "s are"} blocked and need review.`
      : hasActiveDelivery
        ? `${inFlight} delivery package${inFlight === 1 ? " is" : "s are"} in progress or waiting for consumer apply${scopeCount > 0 ? ` across ${scopeCount} scope${scopeCount === 1 ? "" : "s"}` : ""}${writes > 0 ? ` with ${writes} expected writes` : ""}.`
        : eligibleCount > 0
          ? `${eligibleCount} scope${eligibleCount === 1 ? "" : "s"} eligible for delivery package approval.`
          : "No scopes are ready to prepare for consumer inbox delivery.",
    metrics: [
      { label: "Eligible", value: eligibleCount },
      { label: "In flight", value: inFlight },
      { label: "Expected writes", value: writes },
      { label: "Blocked", value: blocked }
    ],
    navigation: { kind: "view", view: "delivery" },
    actionNeeded: eligibleCount > 0 || hasActiveDelivery || blocked > 0
  };
}

function presentApplyVamoStage(
  productionPackage: BatchQueueSnapshot["progress"]["productionPackage"]
): WorkflowNavigatorStagePresentation {
  const pending = productionPackage.applyPending + productionPackage.delivered;
  const applied = productionPackage.applied;
  const failed = productionPackage.applyFailed;
  return {
    key: "apply_vamo",
    label: "Apply in Vamo",
    tone: failed > 0 ? "danger" : pending > 0 ? "watch" : applied > 0 ? "good" : "neutral",
    summary:
      failed > 0
        ? `${failed} package${failed === 1 ? "" : "s"} failed consumer apply and need recovery.`
        : pending > 0
          ? `${pending} package${pending === 1 ? "" : "s"} delivered and waiting for consumer apply.`
          : applied > 0
            ? `${applied} package${applied === 1 ? "" : "s"} applied in Vamo.`
            : "No packages are waiting for consumer apply.",
    metrics: [
      { label: "Pending", value: pending },
      { label: "Applied", value: applied },
      { label: "Failed", value: failed }
    ],
    navigation: { kind: "view", view: "delivery" },
    actionNeeded: failed > 0 || pending > 0
  };
}

function presentNeedsAttentionStage(
  attentionCount: number,
  blockers: BatchQueueSnapshot["blockerSummaries"]
): WorkflowNavigatorStagePresentation {
  const topBlocker = blockers[0]?.reason;
  return {
    key: "needs_attention",
    label: "Needs attention",
    tone: attentionCount > 0 ? "danger" : "good",
    summary:
      attentionCount > 0
        ? topBlocker
          ? `${attentionCount} exception${attentionCount === 1 ? "" : "s"} — top blocker: ${humanizeBlocker(topBlocker)}.`
          : `${attentionCount} scope${attentionCount === 1 ? "" : "s"} need operator attention.`
        : "No active exceptions need triage.",
    metrics: [{ label: "Open", value: attentionCount }],
    navigation: { kind: "view", view: "diagnostics" },
    actionNeeded: attentionCount > 0
  };
}

function sumPlannedRows(
  items?: ReadonlyArray<{ plannedRowCount?: number }>
): number {
  if (!items) {
    return 0;
  }
  return items.reduce((total, item) => total + (item.plannedRowCount ?? 0), 0);
}

function stageKeyForView(view: WorkflowConsoleView): WorkflowNavigatorStageKey {
  switch (view) {
    case "queue":
      return "queue_ready";
    case "agent":
      return "simulate";
    case "staging":
      return "verify_staging";
    case "delivery":
      return "prepare_delivery";
    case "diagnostics":
      return "needs_attention";
    default:
      return "queue_ready";
  }
}

function viewKicker(view: WorkflowConsoleView): string {
  switch (view) {
    case "overview":
      return "Overview";
    case "queue":
      return "Queue";
    case "agent":
      return "Automation";
    case "staging":
      return "Verify";
    case "delivery":
      return "Delivery";
    case "diagnostics":
      return "Diagnostics";
    default:
      return "Ingestion";
  }
}

function viewPurpose(view: WorkflowConsoleView, sourceLabel?: string): string {
  const sourceSuffix = sourceLabel ? ` Data source: ${sourceLabel}.` : "";
  switch (view) {
    case "overview":
      return `Portfolio health across the ingestion pipeline.${sourceSuffix}`;
    case "queue":
      return `Review which scopes are ready, parked, or blocked before simulation.${sourceSuffix}`;
    case "agent":
      return "Preview or run the next bounded automation cycle without changing safety gates.";
    case "staging":
      return "Approve and review staging verification for scopes with simulation evidence.";
    case "delivery":
      return "Approve delivery packages, hand off to the consumer inbox, then apply in Vamo when ready.";
    case "diagnostics":
      return "Triage exceptions, evidence trails, and legacy controls when normal workflow steps stall.";
    default:
      return "Operate ingestion inside policy bounds.";
  }
}

function helpLabelForView(view: WorkflowConsoleView): string {
  switch (view) {
    case "queue":
      return "Queue guide";
    case "agent":
      return "Automation guide";
    case "staging":
      return "Verification guide";
    case "delivery":
      return "Delivery guide";
    case "diagnostics":
      return "Diagnostics guide";
    default:
      return "Workflow guide";
  }
}

function humanizeBlocker(reason: string): string {
  return reason
    .replace(/source_snapshot_empty/g, "snapshot supply missing")
    .replace(/_/g, " ");
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
