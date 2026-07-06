import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  buildAutonomyDashboardView,
  mapPersistedPolicyRow,
  mapPersistedRunRow,
  sampleVamoAutonomyDashboardView
} from "../src/autonomy-read-model.js";

describe("autonomy read model", () => {
  it("maps persisted policy rows into envelopes", () => {
    const envelope = mapPersistedPolicyRow({
      id: "12",
      policyKey: "vamo-eu",
      projectKey: "vamo",
      sourceKey: "fixture-source",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      status: "active",
      allowedTiers: ["staging_canary"],
      allowedGeographies: ["fr"],
      allowedCategories: ["city"],
      allowedTransitions: ["execute_dry_run"],
      maxUnitsPerCycle: 2,
      maxRowsPerCycle: 100,
      rollingLimits: { maxCyclesPerDay: 4 },
      guardThresholds: {},
      productionInboxHandoffPolicy: {},
      policyVersion: 3,
      approvedBy: "operator@example.com",
      approvedAuditId: "audit-9",
      approvalReason: "bounded autonomy",
      summary: { note: "live" }
    });
    assert.equal(envelope.policyId, "12");
    assert.deepEqual(envelope.allowedGeographies, ["fr"]);
    assert.equal(envelope.policyVersion, 3);
  });

  it("maps persisted run rows", () => {
    const run = mapPersistedRunRow({
      runKey: "cycle-1",
      phase: "dry_run",
      status: "paused",
      actorType: "autonomous_agent",
      actorId: "agent-1",
      selectedUnits: ["unit-a"],
      scannedCount: 10,
      advancedCount: 0,
      blockedCount: 1,
      skippedCount: 9,
      pauseReason: "queue_blockers",
      recommendedAction: { action: "pause_for_blocker", summary: "Resolve blockers." },
      dryRunExecutionKey: "batch-dry-run:plan:1",
      waveKey: null,
      packageKey: null,
      startedAt: "2026-07-06T10:00:00.000Z",
      completedAt: null,
      createdAt: "2026-07-06T10:00:00.000Z"
    });
    assert.equal(run.runKey, "cycle-1");
    assert.deepEqual(run.selectedUnitKeys, ["unit-a"]);
    assert.equal(run.dryRunExecutionKey, "batch-dry-run:plan:1");
  });

  it("builds a dashboard view with next-cycle preview", () => {
    const view = sampleVamoAutonomyDashboardView();
    assert.equal(view.projectKey, "vamo");
    assert.ok(view.policy);
    assert.ok(view.nextCycle);
    assert.ok(view.safetySummary.length > 0);
  });

  it("includes pause reason when policy is inactive", () => {
    const view = buildAutonomyDashboardView({
      projectKey: "vamo",
      policy: {
        policyId: "policy-paused",
        policyKey: "paused-policy",
        projectKey: "vamo",
        sourceKey: "fixture-source",
        targetKey: "vamo-place-intelligence",
        targetEnvironment: "staging",
        status: "paused",
        allowedTiers: [],
        allowedGeographies: [],
        allowedCategories: [],
        allowedTransitions: [],
        maxUnitsPerCycle: 1,
        maxRowsPerCycle: 1,
        rollingLimits: {},
        guardThresholds: {},
        productionInboxHandoffPolicy: {},
        policyVersion: 1
      },
      queueSnapshot: null,
      actor: { type: "autonomous_agent", id: "preview" }
    });
    assert.equal(view.nextCycle.decision, "pause");
    assert.equal(view.nextCycle.pauseReasonCode, "policy_inactive");
  });
});
