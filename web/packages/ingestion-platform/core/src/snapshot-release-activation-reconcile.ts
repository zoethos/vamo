/**
 * Supply reconciliation for IP-18.8.11 snapshot release activation.
 *
 * Preserves terminal and in-flight queue evidence while refreshing only
 * source-reconcilable rows from a verified snapshot artifact.
 */

import type { BatchPlanSpec } from "./batch-plan-spec.js";
import {
  buildBatchQueueSnapshotFromItems,
  type BatchQueueItem,
  type BatchQueueSnapshot
} from "./batch-queue-read-model.js";
import {
  BATCH_SNAPSHOT_EMPTY_BLOCK_REASON,
  type BatchSnapshotSourceRow
} from "./batch-snapshot-supply-preview.js";
import { buildFullDataBoundBatchQueueSnapshot } from "./batch-supply-ready-proposal-binding.js";
import { resolveDefaultBatchQueueDisplayFields } from "./consumer-display-fields.js";

const PRESERVED_QUEUE_STATUSES = new Set<BatchQueueItem["status"]>([
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
]);

export interface ReconcileActivatedSnapshotQueueInput {
  currentSnapshot: BatchQueueSnapshot;
  spec: BatchPlanSpec;
  rows: readonly BatchSnapshotSourceRow[];
}

export interface ReconcileActivatedSnapshotQueueResult {
  snapshot: BatchQueueSnapshot;
  changedUnitKeys: string[];
  supplyReadyCount: number;
  parkedCount: number;
  preservedCount: number;
}

export function isSourceReconcilableQueueItem(item: BatchQueueItem): boolean {
  if (item.dryRunReport) {
    return false;
  }
  if (item.crossPlanPackageLifecycle) {
    return false;
  }
  if (PRESERVED_QUEUE_STATUSES.has(item.status)) {
    return false;
  }
  if (item.status === "blocked") {
    return (
      item.blockReasons.length > 0 &&
      item.blockReasons.every((reason) => reason === BATCH_SNAPSHOT_EMPTY_BLOCK_REASON)
    );
  }
  return item.status === "ready_for_dry_run" || item.status === "planned";
}

export function reconcileActivatedSnapshotQueue(
  input: ReconcileActivatedSnapshotQueueInput
): ReconcileActivatedSnapshotQueueResult {
  const fresh = buildFullDataBoundBatchQueueSnapshot({
    spec: input.spec,
    rows: input.rows
  });
  const freshByUnitKey = new Map(fresh.snapshot.items.map((item) => [item.unitKey, item]));

  const changedUnitKeys: string[] = [];
  let preservedCount = 0;

  const items = input.currentSnapshot.items.map((item) => {
    if (!isSourceReconcilableQueueItem(item)) {
      preservedCount += 1;
      return item;
    }

    const next = freshByUnitKey.get(item.unitKey);
    if (!next) {
      preservedCount += 1;
      return item;
    }

    const merged: BatchQueueItem = {
      ...item,
      status: next.status,
      blockReasons: next.blockReasons.slice(),
      proposal: next.proposal ? { ...next.proposal } : null,
      dryRunReport: null
    };

    if (
      merged.status !== item.status ||
      merged.proposal !== item.proposal ||
      merged.blockReasons.join("|") !== item.blockReasons.join("|")
    ) {
      changedUnitKeys.push(item.unitKey);
    }

    return merged;
  });

  const snapshot = buildBatchQueueSnapshotFromItems({
    planId: input.currentSnapshot.planId,
    projectKey: input.currentSnapshot.projectKey,
    targetKey: input.currentSnapshot.targetKey,
    targetEnvironment: input.currentSnapshot.targetEnvironment,
    sourceKey: input.currentSnapshot.sourceKey,
    safetyMode: input.currentSnapshot.safetyMode,
    items,
    planNextAction: fresh.snapshot.nextAction,
    latestExecution: input.currentSnapshot.latestExecution,
    latestWave: input.currentSnapshot.latestWave,
    latestProductionPackageWave: input.currentSnapshot.latestProductionPackageWave,
    displayFields: resolveDefaultBatchQueueDisplayFields({
      projectKey: input.currentSnapshot.projectKey,
      targetKey: input.currentSnapshot.targetKey
    })
  });

  return {
    snapshot,
    changedUnitKeys,
    supplyReadyCount: snapshot.progress.ready,
    parkedCount: snapshot.items.filter(
      (item) =>
        item.status === "blocked" &&
        item.blockReasons.every((reason) => reason === BATCH_SNAPSHOT_EMPTY_BLOCK_REASON)
    ).length,
    preservedCount
  };
}
