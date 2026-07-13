import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  evaluateAutonomyCycle,
  type AutonomyPolicyEnvelope
} from "../src/autonomy-policy.js";
import { sampleVamoEuPoiBatchQueueSnapshot } from "../src/batch-queue-read-model.js";

const autonomousActor = { type: "autonomous_agent" as const, id: "agent-smoke" };

function activePolicy(overrides: Partial<AutonomyPolicyEnvelope> = {}): AutonomyPolicyEnvelope {
  const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
  return {
    policyId: "policy-1",
    policyKey: "vamo-eu-poi-staging",
    projectKey: "vamo",
    sourceKey: snapshot.sourceKey,
    targetKey: snapshot.targetKey,
    targetEnvironment: "staging",
    status: "active",
    allowedTiers: ["sample_dry_run"],
    allowedGeographies: [],
    allowedCategories: [],
    allowedTransitions: ["schedule_dry_run", "execute_dry_run", "approve_staging_wave"],
    maxUnitsPerCycle: 3,
    maxRowsPerCycle: 1000,
    rollingLimits: {},
    guardThresholds: {},
    productionInboxHandoffPolicy: {},
    policyVersion: 1,
    approvalReason: "Autonomy policy smoke",
    approvedAuditId: "audit-1",
    ...overrides
  };
}

describe("autonomy policy", () => {
  it("pauses with no active policy", () => {
    const result = evaluateAutonomyCycle({
      policy: null,
      queueSnapshot: sampleVamoEuPoiBatchQueueSnapshot(),
      actor: autonomousActor
    });
    assert.equal(result.decision, "pause");
    assert.equal(result.pauseReasonCode, "policy_missing");
    assert.equal(result.requiredAction, "wait_for_human");
  });

  it("pauses if target_environment mismatches", () => {
    const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
    const result = evaluateAutonomyCycle({
      policy: activePolicy({ targetEnvironment: "production" }),
      queueSnapshot: snapshot,
      actor: autonomousActor
    });
    assert.equal(result.decision, "pause");
    assert.equal(result.pauseReasonCode, "target_environment_mismatch");
    assert.match(result.pauseReason ?? "", /never inferred from target key/i);
  });

  it("pauses on queue blockers", () => {
    const snapshot = {
      ...sampleVamoEuPoiBatchQueueSnapshot(),
      items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) => ({
        ...item,
        status: "blocked" as const,
        blockReasons: ["fixture:blocked"]
      })),
      blockerSummaries: [{ reason: "fixture:blocked", count: 3 }],
      progress: {
        ...sampleVamoEuPoiBatchQueueSnapshot().progress,
        blocked: 3
      }
    };
    const result = evaluateAutonomyCycle({
      policy: activePolicy(),
      queueSnapshot: snapshot,
      actor: autonomousActor
    });
    assert.equal(result.decision, "pause");
    assert.equal(result.pauseReasonCode, "queue_blockers");
    assert.equal(result.requiredAction, "pause_for_blocker");
  });

  it("continues past parked empty source scopes when supply-ready units remain", () => {
    const base = sampleVamoEuPoiBatchQueueSnapshot();
    const readyCount = 2;
    const parkedCount = base.items.length - readyCount;
    const snapshot = {
      ...base,
      items: base.items.map((item, index) =>
        index < readyCount
          ? {
              ...item,
              status: "ready_for_dry_run" as const,
              blockReasons: []
            }
          : {
              ...item,
              status: "blocked" as const,
              blockReasons: ["source_snapshot_empty"]
            }
      ),
      blockerSummaries: [{ reason: "source_snapshot_empty", count: parkedCount }],
      progress: {
        ...base.progress,
        ready: readyCount,
        blocked: parkedCount
      }
    };
    const result = evaluateAutonomyCycle({
      policy: activePolicy({ maxUnitsPerCycle: 5 }),
      queueSnapshot: snapshot,
      actor: autonomousActor
    });
    assert.equal(result.decision, "continue");
    assert.equal(result.phase, "planning");
    assert.equal(result.requiredAction, "schedule_dry_run");
    assert.deepEqual(
      result.selectedUnitKeys,
      snapshot.items.slice(0, readyCount).map((item) => item.unitKey)
    );
  });

  it("selects dry_run_ready units inside bounds for dry_run phase", () => {
    const snapshot = {
      ...sampleVamoEuPoiBatchQueueSnapshot(),
      items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) => ({
        ...item,
        status: "dry_run_ready" as const
      }))
    };
    const result = evaluateAutonomyCycle({
      policy: activePolicy({
        maxUnitsPerCycle: 2,
        allowedTransitions: ["execute_dry_run"]
      }),
      queueSnapshot: snapshot,
      actor: autonomousActor
    });
    assert.equal(result.decision, "continue");
    assert.equal(result.phase, "dry_run");
    assert.equal(result.requiredAction, "execute_dry_run");
    assert.equal(result.selectedUnitKeys.length, 2);
    assert.ok(result.recommendedAction);
  });

  it("refuses to exceed max_units_per_cycle", () => {
    const snapshot = {
      ...sampleVamoEuPoiBatchQueueSnapshot(),
      items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) => ({
        ...item,
        status: "dry_run_ready" as const,
        dryRunReport: { wroteToTarget: false as const, rowsProcessed: 400, insertCount: 1, updateCount: 0, noOpCount: 0 }
      }))
    };
    const result = evaluateAutonomyCycle({
      policy: activePolicy({ maxUnitsPerCycle: 1, maxRowsPerCycle: 500 }),
      queueSnapshot: snapshot,
      actor: autonomousActor
    });
    assert.equal(result.decision, "continue");
    assert.equal(result.selectedUnitKeys.length, 1);
    assert.equal(result.maxUnitsApplied, 1);
  });

  it("bounds by expected target writes instead of source candidates", () => {
    const snapshot = {
      ...sampleVamoEuPoiBatchQueueSnapshot(),
      items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item, index) => ({
        ...item,
        status: "dry_run_ready" as const,
        dryRunReport: {
          wroteToTarget: false as const,
          rowsProcessed: 300,
          insertCount: 1,
          updateCount: 0,
          noOpCount: 0
        }
      }))
    };
    const result = evaluateAutonomyCycle({
      policy: activePolicy({
        maxUnitsPerCycle: 5,
        maxRowsPerCycle: 2,
        allowedTransitions: ["execute_dry_run"]
      }),
      queueSnapshot: snapshot,
      actor: autonomousActor
    });
    assert.equal(result.decision, "continue");
    assert.equal(result.selectedUnitKeys.length, 2);
    assert.equal(result.maxRowsApplied, 2);
  });

  it("caps autonomous staging-wave preview to the executor staging approval limit", () => {
    const snapshot = {
      ...sampleVamoEuPoiBatchQueueSnapshot(),
      items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) => ({
        ...item,
        status: "dry_run_succeeded" as const,
        dryRunReport: {
          wroteToTarget: false as const,
          rowsProcessed: 1,
          insertCount: 1,
          updateCount: 0,
          noOpCount: 0
        }
      }))
    };
    const result = evaluateAutonomyCycle({
      policy: activePolicy({
        rampMode: "volume_ramp",
        maxUnitsPerCycle: 5,
        maxRowsPerCycle: 100,
        allowedTransitions: ["approve_staging_wave"]
      }),
      queueSnapshot: snapshot,
      actor: autonomousActor
    });

    assert.equal(result.decision, "continue");
    assert.equal(result.phase, "staging_canary");
    assert.equal(result.requiredAction, "approve_or_execute_staging_wave_later");
    assert.equal(result.selectedUnitKeys.length, 1);
    assert.equal(result.maxUnitsApplied, 1);
    assert.equal(result.maxRowsApplied, 1);
  });

  it("pauses production package approval until the policy enables handoff", () => {
    const snapshot = {
      ...sampleVamoEuPoiBatchQueueSnapshot(),
      items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) => ({
        ...item,
        status: "staging_canary_succeeded" as const,
        dryRunReport: {
          wroteToTarget: false as const,
          rowsProcessed: 1,
          insertCount: 1,
          updateCount: 0,
          noOpCount: 0
        }
      }))
    };
    const result = evaluateAutonomyCycle({
      policy: activePolicy({
        allowedTransitions: ["approve_production_package_wave"],
        productionInboxHandoffPolicy: { enabled: false }
      }),
      queueSnapshot: snapshot,
      actor: autonomousActor
    });
    assert.equal(result.decision, "pause");
    assert.equal(result.phase, "production_inbox");
    assert.equal(result.requiredAction, "wait_for_human");
    assert.equal(result.pauseReasonCode, "production_inbox_not_executable");
  });

  it("selects staging-proven units for production package approval when explicitly allowed", () => {
    const snapshot = {
      ...sampleVamoEuPoiBatchQueueSnapshot(),
      items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) => ({
        ...item,
        status: "staging_canary_succeeded" as const,
        dryRunReport: {
          wroteToTarget: false as const,
          rowsProcessed: 1,
          insertCount: 1,
          updateCount: 0,
          noOpCount: 0
        }
      }))
    };
    const result = evaluateAutonomyCycle({
      policy: activePolicy({
        maxUnitsPerCycle: 2,
        allowedTransitions: ["approve_production_package_wave"],
        productionInboxHandoffPolicy: { enabled: true }
      }),
      queueSnapshot: snapshot,
      actor: autonomousActor
    });
    assert.equal(result.decision, "continue");
    assert.equal(result.phase, "production_inbox");
    assert.equal(result.requiredAction, "approve_production_package_wave");
    assert.equal(result.selectedUnitKeys.length, 2);
    assert.equal(result.highestSafetyMode, "production_write");
  });

  it("selects production package units by expected target writes, not source candidates", () => {
    const snapshot = {
      ...sampleVamoEuPoiBatchQueueSnapshot(),
      items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) => ({
        ...item,
        status: "staging_canary_succeeded" as const,
        dryRunReport: {
          wroteToTarget: false as const,
          rowsProcessed: 100,
          insertCount: 1,
          updateCount: 0,
          noOpCount: 0
        }
      }))
    };
    const result = evaluateAutonomyCycle({
      policy: activePolicy({
        maxUnitsPerCycle: 3,
        maxRowsPerCycle: 2,
        allowedTransitions: ["approve_production_package_wave"],
        productionInboxHandoffPolicy: { enabled: true }
      }),
      queueSnapshot: snapshot,
      actor: autonomousActor
    });
    assert.equal(result.decision, "continue");
    assert.equal(result.phase, "production_inbox");
    assert.equal(result.requiredAction, "approve_production_package_wave");
    assert.equal(result.selectedUnitKeys.length, 2);
    assert.equal(result.maxRowsApplied, 2);
  });

  it("continues to deliver an approved production package wave when explicitly allowed", () => {
    const result = evaluateAutonomyCycle({
      policy: activePolicy({
        allowedTransitions: ["deliver_production_package_wave"],
        productionInboxHandoffPolicy: { enabled: true }
      }),
      queueSnapshot: sampleVamoEuPoiBatchQueueSnapshot(),
      productionPackage: {
        waveKey: "batch-production-inbox:sample",
        packageKey: "batch-production-inbox:sample:unit-a",
        status: "approved",
        unitCount: 1,
        totalPlannedRows: 2,
        approvalAuditId: "58",
        items: [{ unitKey: "unit-a", status: "approved", plannedRowCount: 2 }]
      },
      actor: autonomousActor
    });
    assert.equal(result.decision, "continue");
    assert.equal(result.phase, "production_inbox");
    assert.equal(result.requiredAction, "deliver_production_package_wave");
    assert.equal(result.recommendedAction?.evidence?.waveKey, "batch-production-inbox:sample");
  });

  it("surfaces delivered package apply as consumer-owned work", () => {
    const result = evaluateAutonomyCycle({
      policy: activePolicy({
        allowedTransitions: ["apply_consumer_package"],
        productionInboxHandoffPolicy: { enabled: true }
      }),
      queueSnapshot: sampleVamoEuPoiBatchQueueSnapshot(),
      productionPackage: {
        waveKey: "batch-production-inbox:sample",
        packageKey: "batch-production-inbox:sample:unit-a",
        packageId: "batch-production-inbox:sample:unit-a",
        status: "delivered",
        deliveryStatus: "production_inbox_delivered",
        consumerApplyStatus: "pending"
      },
      actor: autonomousActor
    });
    assert.equal(result.decision, "pause");
    assert.equal(result.phase, "production_inbox");
    assert.equal(result.requiredAction, "apply_consumer_package");
    assert.equal(result.pauseReasonCode, "production_inbox_not_executable");
  });

  it("does not park autonomy on delivered packages already applied by the consumer", () => {
    const base = sampleVamoEuPoiBatchQueueSnapshot();
    const snapshot = {
      ...base,
      items: base.items.map((item) => ({
        ...item,
        status: "consumer_applied" as const,
        blockReasons: []
      })),
      blockerSummaries: [],
      progress: {
        ...base.progress,
        planned: 0,
        blocked: 0,
        ready: 0,
        applied: base.items.length,
        productionPackage: {
          ...base.progress.productionPackage,
          delivered: 0,
          applyPending: 0,
          applied: base.items.length,
          blocked: 0
        }
      }
    };
    const result = evaluateAutonomyCycle({
      policy: activePolicy({
        allowedTransitions: [
          "approve_production_package_wave",
          "deliver_production_package_wave",
          "apply_consumer_package"
        ],
        productionInboxHandoffPolicy: { enabled: true }
      }),
      queueSnapshot: snapshot,
      productionPackage: {
        waveKey: "batch-production-inbox:sample",
        packageKey: "batch-production-inbox:sample:unit-a",
        packageId: "batch-production-inbox:sample:unit-a",
        status: "delivered",
        deliveryStatus: "production_inbox_delivered",
        consumerApplyStatus: "applied"
      },
      actor: autonomousActor
    });
    assert.equal(result.decision, "no_op");
    assert.equal(result.requiredAction, "wait_for_human");
  });

  it("never infers environment from target key text", () => {
    const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
    const result = evaluateAutonomyCycle({
      policy: activePolicy({
        targetKey: "vamo-place-intelligence-staging",
        targetEnvironment: "staging"
      }),
      queueSnapshot: {
        ...snapshot,
        targetKey: "vamo-place-intelligence-staging",
        targetEnvironment: "production"
      },
      actor: autonomousActor
    });
    assert.equal(result.decision, "pause");
    assert.equal(result.pauseReasonCode, "target_environment_mismatch");
  });

  it("emits a structured recommended action", () => {
    const snapshot = {
      ...sampleVamoEuPoiBatchQueueSnapshot(),
      items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item, index) =>
        index === 0 ? { ...item, status: "ready_for_dry_run" as const } : item
      )
    };
    const result = evaluateAutonomyCycle({
      policy: activePolicy({ allowedTransitions: ["schedule_dry_run"] }),
      queueSnapshot: snapshot,
      actor: autonomousActor
    });
    assert.equal(result.decision, "continue");
    assert.equal(result.requiredAction, "schedule_dry_run");
    assert.ok(result.recommendedAction);
    assert.match(result.recommendedAction!.summary, /Schedule/i);
    assert.ok(result.telemetry.eventName);
  });
});
