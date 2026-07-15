import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { sampleVamoEuPoiBatchQueueSnapshot } from "../src/batch-queue-read-model.js";
import {
  presentWorkflowDecisionHeader,
  presentWorkflowNavigator,
  type WorkflowDecisionPresenterInput,
  type WorkflowNavigatorPresenterInput
} from "../src/workflow-navigator-presenter.js";

function baseInput(
  overrides: Partial<WorkflowNavigatorPresenterInput> = {}
): WorkflowNavigatorPresenterInput {
  const batchQueue = sampleVamoEuPoiBatchQueueSnapshot();
  return {
    batchQueue,
    batchQueueEligibleCount: 2,
    batchCanaryWaveEligibleCount: 1,
    productionPackageEligibleCount: 0,
    attentionRows: [],
    operatorNextAction: "Run the next bounded simulation cycle.",
    activeView: "overview",
    ...overrides
  };
}

describe("presentWorkflowNavigator", () => {
  it("shows source release as not connected without registered release data", () => {
    const navigator = presentWorkflowNavigator(baseInput());
    const sourceStage = navigator.stages.find((stage) => stage.key === "source_release");
    assert.ok(sourceStage);
    assert.match(sourceStage.summary, /Not connected/i);
    assert.equal(sourceStage.metrics[0]?.value, 0);
    assert.equal(sourceStage.navigation.kind, "href");
    if (sourceStage.navigation.kind === "href") {
      assert.equal(sourceStage.navigation.href, "/admin/providers");
    }
  });

  it("derives queue, simulation, and verification counts from batch progress", () => {
    const navigator = presentWorkflowNavigator(baseInput());
    const queue = navigator.stages.find((stage) => stage.key === "queue_ready");
    const simulate = navigator.stages.find((stage) => stage.key === "simulate");
    const verify = navigator.stages.find((stage) => stage.key === "verify_staging");

    assert.ok(queue);
    assert.ok(simulate);
    assert.ok(verify);
    assert.equal(queue.metrics.length, 4);
    assert.equal(simulate.metrics.length, 4);
    assert.equal(verify.metrics.length, 3);
    assert.equal(queue.navigation.kind, "view");
    assert.equal(simulate.navigation.kind, "view");
    assert.equal(verify.navigation.kind, "view");
    if (queue.navigation.kind === "view") {
      assert.equal(queue.navigation.view, "queue");
    }
    if (simulate.navigation.kind === "view") {
      assert.equal(simulate.navigation.view, "agent");
    }
    if (verify.navigation.kind === "view") {
      assert.equal(verify.navigation.view, "staging");
    }
  });

  it("flags attention when blocker rows are present", () => {
    const batchQueue = sampleVamoEuPoiBatchQueueSnapshot();
    const attentionRows = batchQueue.items.filter((item) => item.blockReasons.length > 0).slice(0, 2);
    const navigator = presentWorkflowNavigator(
      baseInput({
        attentionRows,
        batchQueue
      })
    );
    assert.equal(navigator.attentionCount, attentionRows.length);
    assert.equal(navigator.stages.some((stage) => stage.key === "needs_attention"), false);
    const attention = navigator.attentionStage;
    assert.equal(attention.actionNeeded, attentionRows.length > 0);
    assert.equal(attention.navigation.kind, "view");
    if (attention.navigation.kind === "view") {
      assert.equal(attention.navigation.view, "diagnostics");
    }
  });

  it("keeps empty snapshot scopes parked instead of flagging them as operator attention", () => {
    const batchQueue = sampleVamoEuPoiBatchQueueSnapshot();
    const parkedScope = {
      ...batchQueue.items[0]!,
      status: "blocked" as const,
      blockReasons: ["source_snapshot_empty"]
    };
    const navigator = presentWorkflowNavigator(
      baseInput({
        attentionRows: [parkedScope],
        batchQueue: {
          ...batchQueue,
          items: [parkedScope],
          progress: {
            ...batchQueue.progress,
            planned: 0,
            blocked: 1,
            ready: 0,
            execution: {
              dryRunReady: 0,
              dryRunRunning: 0,
              dryRunSucceeded: 0,
              dryRunBlocked: 0
            }
          },
          blockerSummaries: [{ reason: "source_snapshot_empty", count: 1 }]
        }
      })
    );

    assert.equal(navigator.attentionCount, 0);
    assert.equal(navigator.attentionStage.actionNeeded, false);
    assert.doesNotMatch(navigator.attentionStage.summary, /snapshot supply missing/i);
    const queue = navigator.stages.find((stage) => stage.key === "queue_ready");
    assert.ok(queue);
    assert.match(queue.summary, /parked until snapshot coverage expands/i);
  });

  it("never invents snapshot state when a registered release is absent", () => {
    const navigator = presentWorkflowNavigator(
      baseInput({
        registeredSnapshotRelease: undefined
      })
    );
    const sourceStage = navigator.stages.find((stage) => stage.key === "source_release");
    assert.ok(sourceStage);
    assert.doesNotMatch(sourceStage.summary, /Paris|Barcelona|Lisbon/i);
    assert.match(sourceStage.summary, /Not connected/i);
  });
});

describe("presentWorkflowDecisionHeader", () => {
  it("uses plain operator language for the active tab", () => {
    const header = presentWorkflowDecisionHeader({
      ...baseInput({
        activeView: "queue",
        operatorNextAction: "Approve staging_canary wave W-24 before production_package delivery."
      }),
      batchQueueSourceLabel: "Live control plane"
    } as WorkflowDecisionPresenterInput);
    assert.equal(header.kicker, "Queue");
    assert.doesNotMatch(header.nextAction, /staging_canary/i);
    assert.doesNotMatch(header.nextAction, /production_package/i);
    assert.match(header.purpose, /Live control plane/);
    assert.equal(header.helpSection, "queue");
    assert.equal(header.helpSectionLabel, "Queue guide");
  });
});
