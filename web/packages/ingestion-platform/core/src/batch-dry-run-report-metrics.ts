/**
 * Pure dry-run report metrics for operator-facing staging/delivery views.
 *
 * Distinguishes source candidate volume from expected Vamo target-table writes.
 */

import type { BatchDryRunReport } from "./batch-queue-read-model.js";

export interface BatchDryRunReportMetrics {
  sourceCandidates: number;
  expectedTargetWrites: number;
}

export function extractBatchDryRunReportMetrics(
  report: BatchDryRunReport | null | undefined
): BatchDryRunReportMetrics | null {
  if (!report || report.wroteToTarget !== false) {
    return null;
  }
  return {
    sourceCandidates: report.rowsProcessed,
    expectedTargetWrites: report.insertCount + report.updateCount
  };
}
