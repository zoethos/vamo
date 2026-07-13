import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  sampleVamoEuPoiBatchQueueSnapshot,
  type BatchQueueItem,
  type BatchQueueSnapshot
} from "../src/batch-queue-read-model.js";
import { presentScopeWorkflowContext } from "../src/scope-workflow-presenter.js";
import { presentWorkflowNavigator } from "../src/workflow-navigator-presenter.js";

function withItem(
  snapshot: BatchQueueSnapshot,
  unitKey: string,
  patch: Partial<BatchQueueItem>
): BatchQueueSnapshot {
  return {
    ...snapshot,
    items: snapshot.items.map((item) =>
      item.unitKey === unitKey ? { ...item, ...patch } : item
    )
  };
}

describe("presentScopeWorkflowContext", () => {
  it("returns null without a selected scope", () => {
    const batchQueue = sampleVamoEuPoiBatchQueueSnapshot();
    assert.equal(
      presentScopeWorkflowContext({
        selectedUnitKey: null,
        batchQueue
      }),
      null
    );
  });

  it("derives simulation, staging, delivery, and apply evidence for the selected scope", () => {
    const base = sampleVamoEuPoiBatchQueueSnapshot();
    const unitKey = base.items[0]!.unitKey;
    const batchQueue = withItem(base, unitKey, {
      status: "consumer_apply_pending",
      dryRunReport: {
        wroteToTarget: false,
        rowsProcessed: 12,
        insertCount: 8,
        updateCount: 2,
        noOpCount: 2
      }
    });

    batchQueue.latestWave = {
      waveKey: "staging-wave-1",
      status: "succeeded",
      targetEnvironment: "staging",
      maxUnits: 1,
      maxRows: 50,
      unitCount: 1,
      totalPlannedRows: 10,
      items: [
        {
          unitKey,
          runOrder: 1,
          status: "staging_canary_succeeded",
          plannedRowCount: 10,
          shipmentId: "ship-123",
          blockers: []
        }
      ]
    };

    batchQueue.latestProductionPackageWave = {
      waveKey: "delivery-wave-1",
      status: "delivered",
      targetEnvironment: "production",
      targetKey: batchQueue.targetKey,
      schemaContract: "vamo-place-intelligence@1",
      maxUnits: 1,
      maxRows: 50,
      maxPackages: 1,
      unitCount: 1,
      totalPlannedRows: 10,
      items: [
        {
          unitKey,
          runOrder: 1,
          status: "production_package_delivered",
          plannedRowCount: 10,
          schemaContract: "vamo-place-intelligence@1",
          packageId: "pkg-123",
          consumerApplyStatus: "pending",
          blockers: []
        }
      ]
    };

    const context = presentScopeWorkflowContext({
      selectedUnitKey: unitKey,
      batchQueue,
      deliveryWaveItemsPresentation: [
        {
          unitKey,
          statusPresentation: { label: "Delivered to consumer inbox" },
          consumerApplyStatus: "pending",
          packageId: "pkg-123"
        }
      ]
    });

    assert.ok(context);
    assert.equal(context.unitKey, unitKey);
    assert.equal(context.sourceCandidates, "12");
    assert.equal(context.expectedTargetWrites, "10");
    assert.equal(context.evidenceTrail[0]?.available, true);
    assert.match(context.evidenceTrail[0]?.detail ?? "", /12 source candidates/);
    assert.equal(context.evidenceTrail[1]?.available, true);
    assert.match(context.evidenceTrail[1]?.detail ?? "", /ship-123/);
    assert.equal(context.evidenceTrail[2]?.available, true);
    assert.match(context.evidenceTrail[2]?.status ?? "", /Delivered to consumer inbox/i);
    assert.equal(context.evidenceTrail[3]?.available, true);
    assert.equal(context.evidenceTrail[3]?.status, "Pending");
  });

  it("does not attach latest-wave delivery evidence to a different scope", () => {
    const base = sampleVamoEuPoiBatchQueueSnapshot();
    const selectedKey = base.items[0]!.unitKey;
    const otherKey = base.items[1]?.unitKey ?? `${selectedKey}-other`;
    const batchQueue = withItem(base, selectedKey, {
      status: "staging_canary_succeeded",
      dryRunReport: {
        wroteToTarget: false,
        rowsProcessed: 4,
        insertCount: 2,
        updateCount: 1,
        noOpCount: 1
      }
    });

    batchQueue.latestProductionPackageWave = {
      waveKey: "delivery-wave-other",
      status: "delivered",
      targetEnvironment: "production",
      targetKey: batchQueue.targetKey,
      schemaContract: "vamo-place-intelligence@1",
      maxUnits: 1,
      maxRows: 50,
      maxPackages: 1,
      unitCount: 1,
      totalPlannedRows: 5,
      items: [
        {
          unitKey: otherKey,
          runOrder: 1,
          status: "production_package_delivered",
          plannedRowCount: 5,
          schemaContract: "vamo-place-intelligence@1",
          packageId: "pkg-other",
          consumerApplyStatus: "applied",
          blockers: []
        }
      ]
    };

    const context = presentScopeWorkflowContext({
      selectedUnitKey: selectedKey,
      batchQueue,
      deliveryWaveItemsPresentation: [
        {
          unitKey: otherKey,
          statusPresentation: { label: "Delivered to consumer inbox" },
          consumerApplyStatus: "applied",
          packageId: "pkg-other"
        }
      ]
    });

    assert.ok(context);
    assert.equal(context.evidenceTrail[2]?.available, false);
    assert.equal(context.evidenceTrail[2]?.status, "No record");
    assert.equal(context.evidenceTrail[3]?.available, false);
  });

  it("treats source_snapshot_empty scopes as parked, not operator exceptions", () => {
    const base = sampleVamoEuPoiBatchQueueSnapshot();
    const unitKey = base.items.find((item) => item.status === "blocked")?.unitKey ?? base.items[0]!.unitKey;
    const batchQueue = withItem(base, unitKey, {
      status: "blocked",
      blockReasons: ["source_snapshot_empty"]
    });

    const context = presentScopeWorkflowContext({
      selectedUnitKey: unitKey,
      batchQueue
    });

    assert.ok(context);
    assert.equal(context.isParkedEmptySource, true);
    assert.equal(context.needsAttention, false);
    assert.equal(context.disposition.key, "parked");
    assert.match(context.nextAction, /no operator remediation required/i);
    assert.match(context.workflowStage.summary, /parked until source snapshot coverage expands/i);
  });

  it("leaves portfolio navigator behavior unchanged when no scope is selected", () => {
    const batchQueue = sampleVamoEuPoiBatchQueueSnapshot();
    const navigator = presentWorkflowNavigator({
      batchQueue,
      batchQueueEligibleCount: 2,
      batchCanaryWaveEligibleCount: 1,
      productionPackageEligibleCount: 0,
      attentionRows: [],
      operatorNextAction: "Run the next bounded simulation cycle.",
      activeView: "overview"
    });

    assert.equal(navigator.mode, "portfolio");
    assert.equal(
      presentScopeWorkflowContext({
        selectedUnitKey: null,
        batchQueue
      }),
      null
    );
  });
});
