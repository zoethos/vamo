/**
 * Batch queue dashboard read model — pure transform for IP-18.1.
 *
 * Turns a batch plan into grouped queue/progress state for the Confluendo console.
 * No DB, network, or provider calls. Optional per-unit progression overrides support
 * future persistence slices without changing the snapshot shape.
 */

import type { BatchPlanResult, BatchPlanUnit } from "./batch-planner.js";
import { sampleVamoEuPoiBatchPlan } from "./batch-plan-read-model.js";
import {
  resolveConsumerDisplayFields,
  resolveDefaultBatchQueueDisplayFields,
  type ConsumerDisplayFieldSpec,
  type ResolvedConsumerDisplayField
} from "./consumer-display-fields.js";

export type BatchQueueItemStatus =
  | "planned"
  | "blocked"
  | "ready_for_dry_run"
  | "dry_run_ready"
  | "dry_run_running"
  | "dry_run_succeeded"
  | "dry_run_blocked"
  | "staging_canary_ready"
  | "staging_canary_approved"
  | "staging_canary_running"
  | "staging_canary_succeeded"
  | "staging_canary_blocked"
  | "staged_ready"
  | "production_ready"
  | "applied"
  | "production_package_ready"
  | "production_package_approved"
  | "production_package_delivering"
  | "production_package_delivered"
  | "consumer_apply_pending"
  | "consumer_applied"
  | "consumer_apply_failed"
  | "production_package_blocked";

export const BATCH_QUEUE_ITEM_STATUSES: readonly BatchQueueItemStatus[] = [
  "planned",
  "blocked",
  "ready_for_dry_run",
  "dry_run_ready",
  "dry_run_running",
  "dry_run_succeeded",
  "dry_run_blocked",
  "staging_canary_ready",
  "staging_canary_approved",
  "staging_canary_running",
  "staging_canary_succeeded",
  "staging_canary_blocked",
  "staged_ready",
  "production_ready",
  "applied",
  "production_package_ready",
  "production_package_approved",
  "production_package_delivering",
  "production_package_delivered",
  "consumer_apply_pending",
  "consumer_applied",
  "consumer_apply_failed",
  "production_package_blocked"
];

export interface BatchDryRunReport {
  executionKey?: string;
  wroteToTarget: false;
  rowsProcessed: number;
  insertCount: number;
  updateCount: number;
  noOpCount: number;
  checkpoint?: {
    cursorScope: string;
    cursorValue: string;
    processedCount: number;
  };
  completedAt?: string;
  source?: string;
}

export interface BatchQueueItem {
  unitKey: string;
  runOrder: number;
  geography: string;
  geographyKind: BatchPlanUnit["geographyKind"];
  country: string;
  category: string;
  targetKey: string;
  targetEnvironment: string;
  sourceKey: string;
  priority: number;
  status: BatchQueueItemStatus;
  blockReasons: string[];
  dryRunReport?: BatchDryRunReport | null;
  displayFields?: ResolvedConsumerDisplayField[];
}

export interface BatchQueueGroup {
  groupKey: string;
  groupKind: "country";
  label: string;
  totalUnits: number;
  plannedUnits: number;
  blockedUnits: number;
  readyUnits: number;
  appliedUnits: number;
  items: BatchQueueItem[];
}

export interface BatchQueueCoverage {
  perCountry: Record<string, number>;
  perCategory: Record<string, number>;
  perSource: Record<string, number>;
  /** country -> category -> planned-or-ready unit count */
  matrix: Record<string, Record<string, number>>;
}

export interface BatchQueueStagingCanaryProgress {
  dryRunSucceededEligible: number;
  ready: number;
  approved: number;
  running: number;
  succeeded: number;
  blocked: number;
}

export interface BatchQueueProductionPackageProgress {
  ready: number;
  approved: number;
  delivering: number;
  delivered: number;
  applyPending: number;
  applied: number;
  applyFailed: number;
  blocked: number;
}

export interface BatchQueueLatestProductionPackageWaveItem {
  unitKey: string;
  runOrder: number;
  status: string;
  plannedRowCount: number;
  schemaContract: string;
  packageKey?: string | null;
  packageId?: string | null;
  consumerApplyStatus?: string | null;
  applyEvidence?: Record<string, unknown> | null;
  telemetrySource?: "control" | "inbox" | "missing";
  contentEquivalenceStatus?: "match" | "drift_blocked" | "unavailable";
  contentEquivalenceLabel?: string;
  blockers: string[];
}

export interface BatchQueueLatestProductionPackageWave {
  waveKey: string;
  status: string;
  targetEnvironment: "production";
  targetKey: string;
  schemaContract: string;
  maxUnits: number;
  maxRows: number;
  maxPackages: number;
  unitCount: number;
  totalPlannedRows: number;
  approvalAuditId?: string | null;
  deliveryAuditId?: string | null;
  packageKey?: string | null;
  packageId?: string | null;
  deliveryStatus?: string | null;
  consumerApplyStatus?: string | null;
  consumerApplyEvidence?: Record<string, unknown> | null;
  telemetrySource?: "control" | "inbox" | "missing";
  approvedAt?: string;
  approvalExpiresAt?: string;
  items?: BatchQueueLatestProductionPackageWaveItem[];
}

export interface BatchQueueLatestWaveItem {
  unitKey: string;
  runOrder: number;
  status: string;
  plannedRowCount: number;
  shipmentId?: string | null;
  blockers: string[];
}

export interface BatchQueueLatestWave {
  waveKey: string;
  status: string;
  targetEnvironment: string;
  maxUnits: number;
  maxRows: number;
  unitCount: number;
  totalPlannedRows: number;
  auditId?: string;
  approvalAuditId?: string | null;
  executionAuditId?: string | null;
  approvedAt?: string;
  approvalExpiresAt?: string;
  items?: BatchQueueLatestWaveItem[];
}

export interface BatchQueueExecutionProgress {
  dryRunReady: number;
  dryRunRunning: number;
  dryRunSucceeded: number;
  dryRunBlocked: number;
}

export interface BatchQueueProgress {
  total: number;
  planned: number;
  blocked: number;
  ready: number;
  applied: number;
  execution: BatchQueueExecutionProgress;
  stagingCanary: BatchQueueStagingCanaryProgress;
  productionPackage: BatchQueueProductionPackageProgress;
}

export interface BatchQueueLatestExecution {
  executionKey: string;
  status: string;
  succeededCount: number;
  blockedCount: number;
  runningCount: number;
  auditId?: string;
  finishedAt?: string;
}

export interface BatchQueueBlockerSummary {
  reason: string;
  count: number;
}

export interface BatchQueueSnapshot {
  queueId: string;
  planId: string;
  projectKey: string;
  targetKey: string;
  targetEnvironment: string;
  sourceKey: string;
  safetyMode: string;
  progress: BatchQueueProgress;
  coverage: BatchQueueCoverage;
  groups: BatchQueueGroup[];
  items: BatchQueueItem[];
  blockerSummaries: BatchQueueBlockerSummary[];
  nextAction: string;
  latestExecution?: BatchQueueLatestExecution | null;
  latestWave?: BatchQueueLatestWave | null;
  latestProductionPackageWave?: BatchQueueLatestProductionPackageWave | null;
}

export interface BuildBatchQueueSnapshotInput {
  plan: BatchPlanResult;
  /** Optional per-unit progression overrides keyed by unitKey. */
  progressionByUnitKey?: Readonly<Record<string, BatchQueueItemStatus>>;
  displayFields?: readonly ConsumerDisplayFieldSpec[];
  latestExecution?: BatchQueueLatestExecution | null;
  latestWave?: BatchQueueLatestWave | null;
  latestProductionPackageWave?: BatchQueueLatestProductionPackageWave | null;
}

const READY_STATUSES: readonly BatchQueueItemStatus[] = [
  "ready_for_dry_run",
  "dry_run_ready",
  "staged_ready",
  "production_ready"
];

const BLOCKED_STATUSES: readonly BatchQueueItemStatus[] = [
  "blocked",
  "dry_run_blocked",
  "staging_canary_blocked",
  "production_package_blocked"
];

export function formatBatchQueueBlocker(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    const code = typeof record.code === "string" ? record.code.trim() : "";
    const message = typeof record.message === "string" ? record.message.trim() : "";
    if (code && message) {
      return `${code}: ${message}`;
    }
    if (code) {
      return code;
    }
    if (message) {
      return message;
    }
  }
  return String(value);
}

export function formatBatchQueueBlockers(value: unknown): string[] {
  return Array.isArray(value) ? value.map(formatBatchQueueBlocker) : [];
}

export function buildBatchQueueSnapshot(input: BuildBatchQueueSnapshotInput): BatchQueueSnapshot {
  const items = input.plan.units
    .map((unit) =>
      toQueueItem(unit, input.plan, input.progressionByUnitKey, input.displayFields)
    )
    .sort((a, b) => a.runOrder - b.runOrder);

  return finalizeBatchQueueSnapshot({
    planId: input.plan.planId,
    projectKey: input.plan.projectKey,
    targetKey: input.plan.targetKey,
    targetEnvironment: input.plan.targetEnvironment,
    sourceKey: input.plan.sourceKey,
    safetyMode: input.plan.safetyMode,
    items,
    planNextAction: input.plan.nextAction,
    latestExecution: input.latestExecution,
    latestWave: input.latestWave,
    latestProductionPackageWave: input.latestProductionPackageWave
  });
}

export function buildBatchQueueSnapshotFromPlan(
  plan: BatchPlanResult,
  options: Omit<BuildBatchQueueSnapshotInput, "plan"> = {}
): BatchQueueSnapshot {
  const displayFields =
    options.displayFields ??
    resolveDefaultBatchQueueDisplayFields({
      projectKey: plan.projectKey,
      targetKey: plan.targetKey
    });
  return buildBatchQueueSnapshot({
    plan,
    ...options,
    displayFields
  });
}

export function buildBatchQueueSnapshotFromItems(input: {
  planId: string;
  projectKey: string;
  targetKey: string;
  targetEnvironment: string;
  sourceKey: string;
  safetyMode: string;
  items: BatchQueueItem[];
  planNextAction?: string;
  latestExecution?: BatchQueueLatestExecution | null;
  latestWave?: BatchQueueLatestWave | null;
  latestProductionPackageWave?: BatchQueueLatestProductionPackageWave | null;
  displayFields?: readonly ConsumerDisplayFieldSpec[];
}): BatchQueueSnapshot {
  const displayFields = input.displayFields;
  const items = displayFields
    ? input.items.map((item) => withResolvedDisplayFields(item, displayFields))
    : input.items;
  return finalizeBatchQueueSnapshot({
    planId: input.planId,
    projectKey: input.projectKey,
    targetKey: input.targetKey,
    targetEnvironment: input.targetEnvironment,
    sourceKey: input.sourceKey,
    safetyMode: input.safetyMode,
    items: [...items].sort((a, b) => a.runOrder - b.runOrder),
    planNextAction: input.planNextAction,
    latestExecution: input.latestExecution,
    latestWave: input.latestWave,
    latestProductionPackageWave: input.latestProductionPackageWave
  });
}

function finalizeBatchQueueSnapshot(input: {
  planId: string;
  projectKey: string;
  targetKey: string;
  targetEnvironment: string;
  sourceKey: string;
  safetyMode: string;
  items: BatchQueueItem[];
  planNextAction?: string;
  latestExecution?: BatchQueueLatestExecution | null;
  latestWave?: BatchQueueLatestWave | null;
  latestProductionPackageWave?: BatchQueueLatestProductionPackageWave | null;
}): BatchQueueSnapshot {
  const groups = buildGroups(input.items);
  const coverage = summarizeCoverage(input.items, input.sourceKey);
  const progress = summarizeProgress(input.items);
  const blockerSummaries = summarizeBlockers(input.items);

  return {
    queueId: `${input.planId}-queue`,
    planId: input.planId,
    projectKey: input.projectKey,
    targetKey: input.targetKey,
    targetEnvironment: input.targetEnvironment,
    sourceKey: input.sourceKey,
    safetyMode: input.safetyMode,
    progress,
    coverage,
    groups,
    items: input.items,
    blockerSummaries,
    nextAction: deriveNextAction(
      input.items,
      progress,
      blockerSummaries,
      input.planNextAction ?? "Review batch queue."
    ),
    latestExecution: input.latestExecution ?? null,
    latestWave: input.latestWave ?? null,
    latestProductionPackageWave: input.latestProductionPackageWave ?? null
  };
}

export function sampleVamoEuPoiBatchQueueSnapshot(): BatchQueueSnapshot {
  const plan = sampleVamoEuPoiBatchPlan();
  return buildBatchQueueSnapshot({
    plan,
    displayFields: resolveDefaultBatchQueueDisplayFields({
      projectKey: plan.projectKey,
      targetKey: plan.targetKey
    })
  });
}

function toQueueItem(
  unit: BatchPlanUnit,
  plan: BatchPlanResult,
  progressionByUnitKey?: Readonly<Record<string, BatchQueueItemStatus>>,
  displayFields?: readonly ConsumerDisplayFieldSpec[]
): BatchQueueItem {
  const country = inferCountry(unit);
  return {
    unitKey: unit.unitKey,
    runOrder: unit.runOrder,
    geography: unit.geography,
    geographyKind: unit.geographyKind,
    country,
    category: unit.category,
    targetKey: plan.targetKey,
    targetEnvironment: plan.targetEnvironment,
    sourceKey: plan.sourceKey,
    priority: unit.priority,
    status: resolveQueueStatus(unit, progressionByUnitKey?.[unit.unitKey]),
    blockReasons: unit.blockReasons.slice(),
    displayFields: resolveConsumerDisplayFields(displayFields, {
      scope: {
        category: unit.category,
        geography: unit.geography,
        country
      },
      source: {
        key: plan.sourceKey
      },
      target: {
        key: plan.targetKey,
        environment: plan.targetEnvironment
      }
    })
  };
}

function withResolvedDisplayFields(
  item: BatchQueueItem,
  displayFields: readonly ConsumerDisplayFieldSpec[]
): BatchQueueItem {
  return {
    ...item,
    displayFields: resolveConsumerDisplayFields(displayFields, {
      scope: {
        category: item.category,
        geography: item.geography,
        country: item.country
      },
      source: {
        key: item.sourceKey
      },
      target: {
        key: item.targetKey,
        environment: item.targetEnvironment
      }
    })
  };
}

function resolveQueueStatus(
  unit: BatchPlanUnit,
  override?: BatchQueueItemStatus
): BatchQueueItemStatus {
  if (override) {
    return override;
  }
  if (unit.status === "blocked") {
    return "blocked";
  }
  if (unit.proposal) {
    return "ready_for_dry_run";
  }
  return "planned";
}

function buildGroups(items: BatchQueueItem[]): BatchQueueGroup[] {
  const byCountry = new Map<string, BatchQueueItem[]>();
  for (const item of items) {
    const bucket = byCountry.get(item.country) ?? [];
    bucket.push(item);
    byCountry.set(item.country, bucket);
  }

  return [...byCountry.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([country, groupItems]) => {
      const sortedItems = [...groupItems].sort((a, b) => a.runOrder - b.runOrder);
      return {
        groupKey: country,
        groupKind: "country" as const,
        label: formatCountryLabel(country),
        totalUnits: sortedItems.length,
        plannedUnits: countByStatus(sortedItems, "planned"),
        blockedUnits: countBlocked(sortedItems),
        readyUnits: countReady(sortedItems),
        appliedUnits: countByStatus(sortedItems, "applied"),
        items: sortedItems
      };
    });
}

function summarizeCoverage(items: BatchQueueItem[], sourceKey: string): BatchQueueCoverage {
  const perCountry: Record<string, number> = {};
  const perCategory: Record<string, number> = {};
  const matrix: Record<string, Record<string, number>> = {};

  for (const item of items) {
    if (item.status === "blocked") {
      continue;
    }
    perCountry[item.country] = (perCountry[item.country] ?? 0) + 1;
    perCategory[item.category] = (perCategory[item.category] ?? 0) + 1;
    if (!matrix[item.country]) {
      matrix[item.country] = {};
    }
    matrix[item.country]![item.category] = (matrix[item.country]![item.category] ?? 0) + 1;
  }

  return {
    perCountry,
    perCategory,
    perSource: sourceKey ? { [sourceKey]: items.filter((item) => item.status !== "blocked").length } : {},
    matrix
  };
}

function summarizeProgress(items: BatchQueueItem[]): BatchQueueProgress {
  return {
    total: items.length,
    planned: countByStatus(items, "planned"),
    blocked: countBlocked(items),
    ready: countReady(items),
    applied: countByStatus(items, "applied"),
    execution: {
      dryRunReady: countByStatus(items, "dry_run_ready"),
      dryRunRunning: countByStatus(items, "dry_run_running"),
      dryRunSucceeded: countByStatus(items, "dry_run_succeeded"),
      dryRunBlocked: countByStatus(items, "dry_run_blocked")
    },
    stagingCanary: {
      dryRunSucceededEligible: countDryRunSucceededEligible(items),
      ready: countByStatus(items, "staging_canary_ready"),
      approved: countByStatus(items, "staging_canary_approved"),
      running: countByStatus(items, "staging_canary_running"),
      succeeded: countByStatus(items, "staging_canary_succeeded"),
      blocked: countByStatus(items, "staging_canary_blocked")
    },
    productionPackage: {
      ready: countByStatus(items, "production_package_ready"),
      approved: countByStatus(items, "production_package_approved"),
      delivering: countByStatus(items, "production_package_delivering"),
      delivered: countByStatus(items, "production_package_delivered"),
      applyPending: countByStatus(items, "consumer_apply_pending"),
      applied: countByStatus(items, "consumer_applied"),
      applyFailed: countByStatus(items, "consumer_apply_failed"),
      blocked: countByStatus(items, "production_package_blocked")
    }
  };
}

function countDryRunSucceededEligible(items: BatchQueueItem[]): number {
  return items.filter((item) => {
    if (item.status !== "dry_run_succeeded") {
      return false;
    }
    return item.dryRunReport?.wroteToTarget === false;
  }).length;
}

function summarizeBlockers(items: BatchQueueItem[]): BatchQueueBlockerSummary[] {
  const counts = new Map<string, number>();
  for (const item of items) {
    for (const reason of item.blockReasons) {
      counts.set(reason, (counts.get(reason) ?? 0) + 1);
    }
  }
  return [...counts.entries()]
    .map(([reason, count]) => ({ reason, count }))
    .sort((a, b) => b.count - a.count || a.reason.localeCompare(b.reason));
}

function deriveNextAction(
  items: BatchQueueItem[],
  progress: BatchQueueProgress,
  blockers: BatchQueueBlockerSummary[],
  planNextAction: string
): string {
  if (progress.blocked > 0) {
    const top = blockers[0];
    return top
      ? `Resolve ${progress.blocked} blocked unit(s) — top blocker: ${withTerminalPunctuation(top.reason)}`
      : `Resolve ${progress.blocked} blocked unit(s) before dry-run scheduling.`;
  }
  const readyForDryRun = countByStatus(items, "ready_for_dry_run");
  if (readyForDryRun > 0) {
    return `Review batch queue (${readyForDryRun} ready for dry-run) and approve scheduling.`;
  }
  const dryRunReady = countByStatus(items, "dry_run_ready");
  const dryRunRunning = countByStatus(items, "dry_run_running");
  const dryRunSucceeded = countByStatus(items, "dry_run_succeeded");
  if (dryRunRunning > 0) {
    return `${dryRunRunning} unit(s) dry-run running; ${dryRunSucceeded} succeeded so far.`;
  }
  if (dryRunReady > 0) {
    return `${dryRunReady} unit(s) scheduled for dry-run execution.`;
  }
  if (dryRunSucceeded > 0) {
    const stagingApproved = countByStatus(items, "staging_canary_approved");
    if (stagingApproved > 0) {
      return `${stagingApproved} unit(s) approved for staging-canary wave execution.`;
    }
    return `${dryRunSucceeded} unit(s) completed dry-run execution; review staging-canary wave eligibility.`;
  }
  return planNextAction;
}

function countByStatus(items: BatchQueueItem[], status: BatchQueueItemStatus): number {
  return items.filter((item) => item.status === status).length;
}

function countReady(items: BatchQueueItem[]): number {
  return items.filter((item) => READY_STATUSES.includes(item.status)).length;
}

function countBlocked(items: BatchQueueItem[]): number {
  return items.filter((item) => BLOCKED_STATUSES.includes(item.status)).length;
}

function withTerminalPunctuation(value: string): string {
  return /[.!?]$/.test(value) ? value : `${value}.`;
}

function inferCountry(unit: BatchPlanUnit): string {
  if (unit.geographyKind === "country") {
    return unit.geography;
  }
  const parts = unit.geography.split("-");
  return parts.length > 1 ? parts[parts.length - 1]! : unit.geography;
}

function formatCountryLabel(country: string): string {
  return country
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}
