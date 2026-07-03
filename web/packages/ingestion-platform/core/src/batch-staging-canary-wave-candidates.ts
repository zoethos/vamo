/**
 * Batch wave unit candidate selection — pure helpers for IP-18.5.2.
 *
 * Maps a queue unit's geography/category scope to fixture pipeline candidates.
 * No DB or network access.
 */

import type { StagedCandidate } from "./pipeline-runner.js";
import type { BatchDryRunReport, BatchQueueItem } from "./batch-queue-read-model.js";
import { STAGING_CANARY_MAX_ROWS } from "./staging-canary-policy.js";

export interface BatchWaveUnitScope {
  unitKey: string;
  geography: string;
  category: string;
  maxRows: number;
  expectedWrite: {
    insert: number;
    update: number;
  };
}

export function buildBatchWaveUnitScope(item: BatchQueueItem): BatchWaveUnitScope | null {
  const report = item.dryRunReport;
  if (!report || report.wroteToTarget !== false) {
    return null;
  }
  const writeCount = report.insertCount + report.updateCount;
  if (writeCount < 1) {
    return null;
  }
  return {
    unitKey: item.unitKey,
    geography: item.geography,
    category: item.category,
    maxRows: Math.min(writeCount, STAGING_CANARY_MAX_ROWS),
    expectedWrite: {
      insert: report.insertCount,
      update: report.updateCount
    }
  };
}

export function filterCandidatesForWaveUnit(
  candidates: readonly StagedCandidate[],
  scope: Pick<BatchWaveUnitScope, "geography" | "category">
): StagedCandidate[] {
  return candidates.filter((candidate) => candidateMatchesScope(candidate, scope));
}

export function countCandidateTargetRows(candidates: readonly StagedCandidate[]): number {
  return candidates.reduce((total, candidate) => {
    return total + Object.keys(candidate.payload).length;
  }, 0);
}

export function buildWaveUnitShipmentKey(waveKey: string, unitKey: string): string {
  return `batch-staging-canary-wave:${waveKey}:unit:${unitKey}`;
}

export function parseDryRunWriteCounts(report: BatchDryRunReport | null | undefined): {
  insert: number;
  update: number;
  writeCount: number;
} {
  const insert = report?.insertCount ?? 0;
  const update = report?.updateCount ?? 0;
  return { insert, update, writeCount: insert + update };
}

function candidateMatchesScope(
  candidate: StagedCandidate,
  scope: Pick<BatchWaveUnitScope, "geography" | "category">
): boolean {
  return (
    normalizeScope(candidate.sourceScope?.geography) === normalizeScope(scope.geography) &&
    normalizeScope(candidate.sourceScope?.category) === normalizeScope(scope.category)
  );
}

function normalizeScope(value: string | undefined): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}
