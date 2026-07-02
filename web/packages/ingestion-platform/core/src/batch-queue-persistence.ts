/**
 * Batch queue persistence mapper — pure transforms between dashboard snapshots
 * and control-plane row shapes. No DB or network calls.
 */

import type { BatchPlanSpec } from "./batch-plan-spec.js";
import {
  BATCH_QUEUE_ITEM_STATUSES,
  buildBatchQueueSnapshotFromItems,
  type BatchQueueBlockerSummary,
  type BatchQueueCoverage,
  type BatchQueueItem,
  type BatchQueueItemStatus,
  type BatchQueueProgress,
  type BatchQueueSnapshot
} from "./batch-queue-read-model.js";

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
  items: PersistedBatchQueueItemRow[]
): BatchQueueSnapshot {
  for (const item of items) {
    assertValidQueueItemStatus(item.status);
  }

  const queueItems = items
    .map((row) => mapPersistenceRowToQueueItem(row))
    .sort((a, b) => a.runOrder - b.runOrder);

  return buildBatchQueueSnapshotFromItems({
    planId: plan.planKey,
    projectKey,
    targetKey: plan.targetKey,
    targetEnvironment: plan.targetEnvironment,
    sourceKey: plan.sourceKey,
    safetyMode: plan.safetyMode,
    items: queueItems,
    planNextAction: plan.planSummary.nextAction
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
    proposal: null,
    runReport: null
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
    blockReasons: row.blockers.slice()
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
