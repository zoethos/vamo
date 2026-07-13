/**
 * Batch queue persistence mapper — pure transforms between dashboard snapshots
 * and control-plane row shapes. No DB or network calls.
 */

import type { BatchPlanSpec } from "./batch-plan-spec.js";
import type { CrossPlanPackageLifecycle } from "./batch-cross-plan-package-lifecycle.js";
import {
  BATCH_QUEUE_ITEM_STATUSES,
  buildBatchQueueSnapshotFromItems,
  type BatchDryRunReport,
  type BatchQueueBlockerSummary,
  type BatchQueueCoverage,
  type BatchQueueItem,
  type BatchQueueItemStatus,
  type BatchQueueLatestExecution,
  type BatchQueueLatestProductionPackageWave,
  type BatchQueueLatestWave,
  type BatchQueueProgress,
  type BatchQueueSnapshot
} from "./batch-queue-read-model.js";
import { resolveDefaultBatchQueueDisplayFields } from "./consumer-display-fields.js";

export interface PersistedBatchPlanRow {
  planKey: string;
  sourceKey: string;
  targetKey: string;
  targetEnvironment: "staging" | "production";
  safetyMode: string;
  spec: Record<string, unknown>;
  planSummary: BatchPlanSummaryPayload;
  status: "active" | "archived";
}

export interface BatchPlanSummaryPayload {
  queueId: string;
  projectKey: string;
  nextAction: string;
  progress: BatchQueueProgress;
  coverage: BatchQueueCoverage;
  blockerSummaries: BatchQueueBlockerSummary[];
}

export interface PersistedBatchQueueItemRow {
  unitKey: string;
  countryCode: string;
  geographyKey: string;
  geographyLabel: string | null;
  geographyKind: string;
  category: string;
  sourceKey: string;
  targetKey: string;
  targetEnvironment: "staging" | "production";
  status: BatchQueueItemStatus;
  priority: number;
  runOrder: number;
  blockers: string[];
  proposal: Record<string, unknown> | null;
  runReport: Record<string, unknown> | null;
}

export interface BatchQueuePersistenceBundle {
  plan: PersistedBatchPlanRow;
  items: PersistedBatchQueueItemRow[];
}

export function mapSnapshotToPersistenceBundle(
  snapshot: BatchQueueSnapshot,
  spec: BatchPlanSpec | Record<string, unknown>,
  options?: { planStatus?: "active" | "archived" }
): BatchQueuePersistenceBundle {
  for (const item of snapshot.items) {
    assertValidQueueItemStatus(item.status);
  }

  return {
    plan: {
      planKey: snapshot.planId,
      sourceKey: snapshot.sourceKey,
      targetKey: snapshot.targetKey,
      targetEnvironment: snapshot.targetEnvironment as "staging" | "production",
      safetyMode: snapshot.safetyMode,
      spec: isBatchPlanSpec(spec) ? batchPlanSpecToRecord(spec) : spec,
      planSummary: {
        queueId: snapshot.queueId,
        projectKey: snapshot.projectKey,
        nextAction: snapshot.nextAction,
        progress: snapshot.progress,
        coverage: snapshot.coverage,
        blockerSummaries: snapshot.blockerSummaries
      },
      status: options?.planStatus ?? "active"
    },
    items: snapshot.items.map((item) => mapQueueItemToPersistenceRow(item))
  };
}

export function mapPersistenceBundleToSnapshot(
  projectKey: string,
  plan: PersistedBatchPlanRow,
  items: PersistedBatchQueueItemRow[],
  latestExecution?: BatchQueueLatestExecution | null,
  latestWave?: BatchQueueLatestWave | null,
  latestProductionPackageWave?: BatchQueueLatestProductionPackageWave | null,
  options?: {
    crossPlanPackageLifecycleByUnitKey?: Readonly<Record<string, CrossPlanPackageLifecycle>>;
  }
): BatchQueueSnapshot {
  for (const item of items) {
    assertValidQueueItemStatus(item.status);
  }

  const queueItems = items
    .map((row) => {
      const item = mapPersistenceRowToQueueItem(row);
      const crossPlanPackageLifecycle = options?.crossPlanPackageLifecycleByUnitKey?.[item.unitKey];
      return crossPlanPackageLifecycle ? { ...item, crossPlanPackageLifecycle } : item;
    })
    .sort((a, b) => a.runOrder - b.runOrder);

  return buildBatchQueueSnapshotFromItems({
    planId: plan.planKey,
    projectKey,
    targetKey: plan.targetKey,
    targetEnvironment: plan.targetEnvironment,
    sourceKey: plan.sourceKey,
    safetyMode: plan.safetyMode,
    items: queueItems,
    planNextAction: plan.planSummary.nextAction,
    latestExecution: latestExecution ?? null,
    latestWave: latestWave ?? null,
    latestProductionPackageWave: latestProductionPackageWave ?? null,
    displayFields: resolveDefaultBatchQueueDisplayFields({
      projectKey,
      targetKey: plan.targetKey
    })
  });
}

export function assertValidQueueItemStatus(status: string): asserts status is BatchQueueItemStatus {
  if (!(BATCH_QUEUE_ITEM_STATUSES as readonly string[]).includes(status)) {
    throw new Error(`Invalid batch queue item status "${status}".`);
  }
}

function mapQueueItemToPersistenceRow(item: BatchQueueItem): PersistedBatchQueueItemRow {
  return {
    unitKey: item.unitKey,
    countryCode: item.country,
    geographyKey: item.geography,
    geographyLabel: item.geography,
    geographyKind: item.geographyKind,
    category: item.category,
    sourceKey: item.sourceKey,
    targetKey: item.targetKey,
    targetEnvironment: item.targetEnvironment as "staging" | "production",
    status: item.status,
    priority: item.priority,
    runOrder: item.runOrder,
    blockers: item.blockReasons.slice(),
    proposal: item.proposal ? { ...item.proposal } : null,
    runReport: item.dryRunReport ? { ...item.dryRunReport } : null
  };
}

function mapPersistenceRowToQueueItem(row: PersistedBatchQueueItemRow): BatchQueueItem {
  return {
    unitKey: row.unitKey,
    runOrder: row.runOrder,
    geography: row.geographyKey,
    geographyKind: row.geographyKind as BatchQueueItem["geographyKind"],
    country: row.countryCode,
    category: row.category,
    targetKey: row.targetKey,
    targetEnvironment: row.targetEnvironment,
    sourceKey: row.sourceKey,
    priority: row.priority,
    status: row.status,
    blockReasons: row.blockers.slice(),
    dryRunReport: parseDryRunReport(row.runReport)
  };
}

function parseDryRunReport(value: Record<string, unknown> | null): BatchDryRunReport | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  return {
    executionKey: typeof value.executionKey === "string" ? value.executionKey : undefined,
    wroteToTarget: false,
    rowsProcessed: Number(value.rowsProcessed ?? 0),
    insertCount: Number(value.insertCount ?? 0),
    updateCount: Number(value.updateCount ?? 0),
    noOpCount: Number(value.noOpCount ?? 0),
    checkpoint:
      value.checkpoint && typeof value.checkpoint === "object"
        ? {
            cursorScope: String((value.checkpoint as Record<string, unknown>).cursorScope ?? ""),
            cursorValue: String((value.checkpoint as Record<string, unknown>).cursorValue ?? ""),
            processedCount: Number((value.checkpoint as Record<string, unknown>).processedCount ?? 0)
          }
        : undefined,
    completedAt: typeof value.completedAt === "string" ? value.completedAt : undefined,
    source: typeof value.source === "string" ? value.source : undefined
  };
}

function isBatchPlanSpec(value: BatchPlanSpec | Record<string, unknown>): value is BatchPlanSpec {
  return typeof value === "object" && value !== null && value.kind === "ingestion.batch_plan";
}

function batchPlanSpecToRecord(spec: BatchPlanSpec): Record<string, unknown> {
  return {
    kind: spec.kind,
    version: spec.version,
    id: spec.id,
    projectKey: spec.projectKey,
    sourceKey: spec.sourceKey,
    targetProfileKey: spec.targetProfileKey,
    targetKey: spec.targetKey,
    targetEnvironment: spec.targetEnvironment,
    safetyMode: spec.safetyMode,
    geographies: spec.geographies,
    categories: spec.categories,
    priorityHints: spec.priorityHints,
    bounds: spec.bounds,
    notes: spec.notes
  };
}
