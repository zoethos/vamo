/**
 * Batch queue dashboard read model — pure transform for IP-18.1.
 *
 * Turns a batch plan into grouped queue/progress state for the Confluendo console.
 * No DB, network, or provider calls. Optional per-unit progression overrides support
 * future persistence slices without changing the snapshot shape.
 */

import type { BatchPlanResult, BatchPlanUnit } from "./batch-planner.js";
import { sampleVamoEuPoiBatchPlan } from "./batch-plan-read-model.js";

export type BatchQueueItemStatus =
  | "planned"
  | "blocked"
  | "ready_for_dry_run"
  | "dry_run_ready"
  | "dry_run_running"
  | "dry_run_succeeded"
  | "dry_run_blocked"
  | "staged_ready"
  | "production_ready"
  | "applied";

export const BATCH_QUEUE_ITEM_STATUSES: readonly BatchQueueItemStatus[] = [
  "planned",
  "blocked",
  "ready_for_dry_run",
  "dry_run_ready",
  "dry_run_running",
  "dry_run_succeeded",
  "dry_run_blocked",
  "staged_ready",
  "production_ready",
  "applied"
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
}

export interface BuildBatchQueueSnapshotInput {
  plan: BatchPlanResult;
  /** Optional per-unit progression overrides keyed by unitKey. */
  progressionByUnitKey?: Readonly<Record<string, BatchQueueItemStatus>>;
  latestExecution?: BatchQueueLatestExecution | null;
}

const READY_STATUSES: readonly BatchQueueItemStatus[] = [
  "ready_for_dry_run",
  "dry_run_ready",
  "staged_ready",
  "production_ready"
];

export function buildBatchQueueSnapshot(input: BuildBatchQueueSnapshotInput): BatchQueueSnapshot {
  const items = input.plan.units
    .map((unit) => toQueueItem(unit, input.plan, input.progressionByUnitKey))
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
    latestExecution: input.latestExecution
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
}): BatchQueueSnapshot {
  const items = [...input.items].sort((a, b) => a.runOrder - b.runOrder);
  return finalizeBatchQueueSnapshot({
    planId: input.planId,
    projectKey: input.projectKey,
    targetKey: input.targetKey,
    targetEnvironment: input.targetEnvironment,
    sourceKey: input.sourceKey,
    safetyMode: input.safetyMode,
    items,
    planNextAction: input.planNextAction,
    latestExecution: input.latestExecution
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
    latestExecution: input.latestExecution ?? null
  };
}

export function sampleVamoEuPoiBatchQueueSnapshot(): BatchQueueSnapshot {
  return buildBatchQueueSnapshot({ plan: sampleVamoEuPoiBatchPlan() });
}

function toQueueItem(
  unit: BatchPlanUnit,
  plan: BatchPlanResult,
  progressionByUnitKey?: Readonly<Record<string, BatchQueueItemStatus>>
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
    blockReasons: unit.blockReasons.slice()
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
        blockedUnits: countByStatus(sortedItems, "blocked"),
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
    blocked: countByStatus(items, "blocked"),
    ready: countReady(items),
    applied: countByStatus(items, "applied"),
    execution: {
      dryRunReady: countByStatus(items, "dry_run_ready"),
      dryRunRunning: countByStatus(items, "dry_run_running"),
      dryRunSucceeded: countByStatus(items, "dry_run_succeeded"),
      dryRunBlocked: countByStatus(items, "dry_run_blocked")
    }
  };
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
      ? `Resolve ${progress.blocked} blocked unit(s) — top blocker: ${top.reason}.`
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
    return `${dryRunSucceeded} unit(s) completed dry-run execution.`;
  }
  return planNextAction;
}

function countByStatus(items: BatchQueueItem[], status: BatchQueueItemStatus): number {
  return items.filter((item) => item.status === status).length;
}

function countReady(items: BatchQueueItem[]): number {
  return items.filter((item) => READY_STATUSES.includes(item.status)).length;
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
