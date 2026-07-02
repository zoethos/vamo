import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  evaluateBatchStagingCanaryWaveExecution,
  type BatchStagingCanaryWaveExecutionBlockCode
} from "../src/batch-staging-canary-wave-execution-policy.js";
import type { LoadedStagingCanaryWave } from "../src/batch-staging-canary-wave-load.js";

const NOW = "2026-07-02T14:00:00.000Z";
const FRESH_EXPIRY = "2026-07-02T15:00:00.000Z";
const STALE_EXPIRY = "2026-07-02T13:00:00.000Z";

describe("evaluateBatchStagingCanaryWaveExecution", () => {
  it("accepts approved wave with pending items", () => {
    const result = evaluateBatchStagingCanaryWaveExecution({
      projectKey: "vamo",
      targetEnvironment: "staging",
      wave: sampleWave(),
      now: NOW
    });
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.plan.pendingUnitKeys.length, 1);
    assert.equal(result.plan.unitPlans[0]?.status, "pending");
    assert.match(result.plan.unitPlans[0]?.shipmentKey ?? "", /^batch-staging-canary-wave:/);
  });

  it("blocks production environment", () => {
    const result = evaluateBatchStagingCanaryWaveExecution({
      projectKey: "vamo",
      targetEnvironment: "production",
      wave: sampleWave(),
      now: NOW
    });
    assertBlocked(result, "production_environment_forbidden");
  });

  it("blocks missing wave", () => {
    const result = evaluateBatchStagingCanaryWaveExecution({
      projectKey: "vamo",
      targetEnvironment: "staging",
      wave: null,
      now: NOW
    });
    assertBlocked(result, "wave_not_found");
  });

  it("blocks expired approval", () => {
    const result = evaluateBatchStagingCanaryWaveExecution({
      projectKey: "vamo",
      targetEnvironment: "staging",
      wave: sampleWave({ approvalExpiresAt: STALE_EXPIRY }),
      now: NOW
    });
    assertBlocked(result, "approval_expired");
  });

  it("blocks non-executable wave status", () => {
    const result = evaluateBatchStagingCanaryWaveExecution({
      projectKey: "vamo",
      targetEnvironment: "staging",
      wave: sampleWave({ status: "failed" }),
      now: NOW
    });
    assertBlocked(result, "wave_not_executable");
  });

  it("blocks when no pending items remain", () => {
    const result = evaluateBatchStagingCanaryWaveExecution({
      projectKey: "vamo",
      targetEnvironment: "staging",
      wave: sampleWave({
        items: [
          {
            id: "1",
            unitKey: "unit-a",
            runOrder: 1,
            status: "succeeded",
            plannedRowCount: 2,
            blockers: [],
            shipmentId: "10"
          }
        ]
      }),
      now: NOW
    });
    assertBlocked(result, "no_pending_items");
  });

  it("skips succeeded items and respects maxUnits/maxRows bounds", () => {
    const result = evaluateBatchStagingCanaryWaveExecution({
      projectKey: "vamo",
      targetEnvironment: "staging",
      wave: sampleWave({
        items: [
          {
            id: "1",
            unitKey: "unit-a",
            runOrder: 1,
            status: "succeeded",
            plannedRowCount: 2,
            blockers: [],
            shipmentId: "10"
          },
          {
            id: "2",
            unitKey: "unit-b",
            runOrder: 2,
            status: "approved",
            plannedRowCount: 3,
            blockers: [],
            shipmentId: null
          },
          {
            id: "3",
            unitKey: "unit-c",
            runOrder: 3,
            status: "approved",
            plannedRowCount: 4,
            blockers: [],
            shipmentId: null
          }
        ]
      }),
      maxUnits: 1,
      maxRows: 3,
      now: NOW
    });
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.deepEqual(result.plan.pendingUnitKeys, ["unit-b"]);
    assert.equal(result.plan.unitPlans.filter((plan) => plan.status === "skip_succeeded").length, 1);
  });
});

function assertBlocked(
  result: ReturnType<typeof evaluateBatchStagingCanaryWaveExecution>,
  code: BatchStagingCanaryWaveExecutionBlockCode
) {
  assert.equal(result.ok, false);
  if (result.ok) return;
  assert.ok(result.blocks.some((block) => block.code === code), `expected block ${code}`);
}

function sampleWave(overrides: Partial<LoadedStagingCanaryWave> = {}): LoadedStagingCanaryWave {
  return {
    id: "7",
    waveKey: "batch-staging-canary:vamo-eu-poi-sample:audit:wave-smoke",
    batchPlanId: "3",
    planKey: "vamo-eu-poi-sample",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    maxUnits: 1,
    maxRows: 50,
    status: "approved",
    auditReason: "Approve first wave.",
    approvalAuditId: "42",
    approvedAt: NOW,
    approvalExpiresAt: FRESH_EXPIRY,
    summary: {},
    items: [
      {
        id: "11",
        unitKey: "vamo-place-intelligence:rome-italy:poi",
        runOrder: 1,
        status: "approved",
        plannedRowCount: 2,
        blockers: [],
        shipmentId: null
      }
    ],
    ...overrides
  };
}
