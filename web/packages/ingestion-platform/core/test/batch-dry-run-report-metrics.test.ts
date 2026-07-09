import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { extractBatchDryRunReportMetrics } from "../src/batch-dry-run-report-metrics.js";

describe("extractBatchDryRunReportMetrics", () => {
  it("separates source candidates from expected target writes", () => {
    const metrics = extractBatchDryRunReportMetrics({
      wroteToTarget: false,
      rowsProcessed: 7,
      insertCount: 2,
      updateCount: 1,
      noOpCount: 4
    });

    assert.deepEqual(metrics, {
      sourceCandidates: 7,
      expectedTargetWrites: 3
    });
  });

  it("returns null when wroteToTarget is not false", () => {
    assert.equal(
      extractBatchDryRunReportMetrics({
        wroteToTarget: true as unknown as false,
        rowsProcessed: 1,
        insertCount: 1,
        updateCount: 0,
        noOpCount: 0
      }),
      null
    );
  });
});
