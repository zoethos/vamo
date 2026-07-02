import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { evaluateBatchDryRunExecution } from "../src/batch-dry-run-execution-policy.js";
import { sampleVamoEuPoiBatchQueueSnapshot } from "../src/batch-queue-read-model.js";

describe("batch dry-run execution policy", () => {
  it("selects bounded dry_run_ready units for the explicit target environment", () => {
    const snapshot = {
      ...sampleVamoEuPoiBatchQueueSnapshot(),
      items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) => ({
        ...item,
        status: "dry_run_ready" as const
      }))
    };

    const result = evaluateBatchDryRunExecution({
      projectKey: "vamo",
      snapshot,
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      maxUnits: 3,
      auditReason: "IP-18.4 bounded dry-run execution preview",
      auditId: "15",
      actor: { type: "operator", id: "operator-smoke" }
    });

    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.plan.unitKeys.length, 3);
    assert.equal(result.plan.targetKey, "vamo-place-intelligence");
    assert.equal(result.plan.targetEnvironment, "staging");
    assert.match(result.plan.executionKey, /audit:15/);
    assert.ok(result.plan.safetySummary.some((line) => /No Vamo staging writes/i.test(line)));
  });

  it("rejects execution without an audit reason", () => {
    const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
    const result = evaluateBatchDryRunExecution({
      projectKey: "vamo",
      snapshot,
      targetKey: snapshot.targetKey,
      targetEnvironment: snapshot.targetEnvironment,
      maxUnits: 1,
      auditReason: "   ",
      actor: { type: "operator", id: "operator-smoke" }
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.ok(result.blocks.some((block) => block.code === "audit_reason_required"));
  });

  it("rejects when no dry_run_ready units exist", () => {
    const result = evaluateBatchDryRunExecution({
      projectKey: "vamo",
      snapshot: sampleVamoEuPoiBatchQueueSnapshot(),
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      maxUnits: 2,
      auditReason: "attempt without scheduled units",
      actor: { type: "operator", id: "operator-smoke" }
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.ok(result.blocks.some((block) => block.code === "no_eligible_items"));
  });
});
