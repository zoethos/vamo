/**
 * Bounded batch dry-run simulator — fixture-only, no provider or target writes.
 *
 * Produces deterministic per-unit dry-run reports for IP-18.4 control-plane
 * execution. Uses bundled fixture semantics only; never opens network connections.
 */

export interface BatchDryRunCheckpoint {
  cursorScope: string;
  cursorValue: string;
  processedCount: number;
}

export interface BatchDryRunUnitReport {
  executionKey: string;
  unitKey: string;
  geography: string;
  category: string;
  targetKey: string;
  targetEnvironment: string;
  wroteToTarget: false;
  rowsProcessed: number;
  insertCount: number;
  updateCount: number;
  noOpCount: number;
  checkpoint: BatchDryRunCheckpoint;
  completedAt: string;
  source: "fixture_simulation";
}

export interface SimulateBatchDryRunUnitInput {
  executionKey: string;
  unitKey: string;
  geography: string;
  category: string;
  targetKey: string;
  targetEnvironment: string;
  candidateCount?: number;
  rowLimit?: number;
  now?: string;
}

export function simulateBatchDryRunUnit(input: SimulateBatchDryRunUnitInput): BatchDryRunUnitReport {
  const rowLimit = input.rowLimit ?? 3;
  const sourceRowCount = input.candidateCount ?? deterministicRowCount(input.unitKey);
  const rowsProcessed = Math.min(rowLimit, sourceRowCount);
  const insertCount = rowsProcessed;
  const updateCount = 0;
  const noOpCount = 0;

  return {
    executionKey: input.executionKey,
    unitKey: input.unitKey,
    geography: input.geography,
    category: input.category,
    targetKey: input.targetKey,
    targetEnvironment: input.targetEnvironment,
    wroteToTarget: false,
    rowsProcessed,
    insertCount,
    updateCount,
    noOpCount,
    checkpoint: {
      cursorScope: `${input.geography}:${input.category}`,
      cursorValue: String(rowsProcessed),
      processedCount: rowsProcessed
    },
    completedAt: input.now ?? new Date().toISOString(),
    source: "fixture_simulation"
  };
}

function deterministicRowCount(unitKey: string): number {
  let hash = 0;
  for (const char of unitKey) {
    hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  }
  return (hash % 3) + 1;
}
