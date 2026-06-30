import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  buildProgressiveRunView,
  isActiveCanaryShipment,
  sampleProgressiveRunSnapshot,
  sampleVamoProposal,
  type CanaryShipmentState,
  type ProgressiveRunSnapshot
} from "../src/progressive-read-model.js";

describe("progressive run dashboard read model", () => {
  it("surfaces tier, rationale, progress, blockers, and the next action", () => {
    const view = buildProgressiveRunView(sampleProgressiveRunSnapshot);

    const vamo = view.rows.find((row) => row.targetId === "vamo-place-intelligence-staging");
    assert.ok(vamo);
    assert.equal(vamo!.workStatus, "review_required");
    assert.equal(vamo!.tier, "sample_dry_run");
    assert.equal(vamo!.safetyMode, "dry_run");
    assert.equal(vamo!.stage, "review_required");
    assert.ok(vamo!.rationale.length > 0);
    assert.ok(vamo!.score > 0);
    assert.equal(vamo!.eligible, true);

    // Advisory AI rationale is surfaced (deterministic placeholder, not an LLM).
    assert.ok(vamo!.aiSummary.length > 0);
    assert.match(vamo!.aiSummary, /Advisory/);
    assert.equal(vamo!.aiConfidence, "high");
    assert.equal(vamo!.aiRecommendedTier, "sample_dry_run");

    // Progress, checkpoint, and shipment diff are visible.
    assert.equal(vamo!.rowsRead, 5);
    assert.equal(vamo!.rowsStaged, 1);
    assert.match(vamo!.checkpoint, /source_row_id=/);
    assert.match(vamo!.shipmentDiff, /2 insert/);
    assert.deepEqual(vamo!.canaryBounds, {
      geography: "rome-italy",
      category: "poi",
      maxRows: 2
    });
    assert.ok(vamo!.policyBlocks.length >= 1);
    assert.ok(vamo!.policyBlocks.some((block) => block.includes("scope_mismatch")));
    assert.ok(vamo!.deadLetters.length >= 1);
    assert.match(vamo!.nextApproval, /staging canary/i);
  });

  it("flags blocked targets with their blocking gates", () => {
    const view = buildProgressiveRunView(sampleProgressiveRunSnapshot);
    const blocked = view.rows.find((row) => row.workStatus === "blocked");

    assert.ok(blocked);
    assert.equal(blocked!.eligible, false);
    assert.ok(blocked!.blockers.includes("source_rights"));
    assert.equal(blocked!.tone, "danger");
  });

  it("summarizes the backlog and the single next action", () => {
    const view = buildProgressiveRunView(sampleProgressiveRunSnapshot);

    assert.equal(view.summary.reviewRequired, 1);
    assert.equal(view.summary.blocked, 1);
    assert.match(view.nextAction, /Review vamo-place-intelligence-staging/);
  });

  it("derives a deterministic, dry-run-only sample proposal", () => {
    const a = sampleVamoProposal();
    const b = sampleVamoProposal();

    assert.equal(a.ok, true);
    assert.deepEqual(a, b);
    if (a.ok) {
      assert.equal(a.proposal.safetyMode, "dry_run");
      assert.equal(a.proposal.tier, "sample_dry_run");
    }
  });

  it("is deterministic for the same snapshot", () => {
    assert.deepEqual(
      buildProgressiveRunView(sampleProgressiveRunSnapshot),
      buildProgressiveRunView(sampleProgressiveRunSnapshot)
    );
  });

  it("classifies active vs. inactive canary shipment statuses", () => {
    const base = {
      mode: "approved_write",
      shipmentKey: "staging-canary:t:approval:1",
      createdAt: "2026-06-28T12:00:00.000Z"
    };
    assert.equal(isActiveCanaryShipment(undefined), false);
    assert.equal(isActiveCanaryShipment(null), false);
    assert.equal(isActiveCanaryShipment({ ...base, status: "succeeded" }), true);
    assert.equal(isActiveCanaryShipment({ ...base, status: "shipping" }), true);
    assert.equal(isActiveCanaryShipment({ ...base, status: "approved" }), true);
    assert.equal(isActiveCanaryShipment({ ...base, status: "failed" }), false);
    assert.equal(isActiveCanaryShipment({ ...base, status: "planned" }), false);
  });

  it("surfaces a succeeded shipment as already shipped, taking precedence over review_required", () => {
    const shipment: CanaryShipmentState = {
      status: "succeeded",
      mode: "approved_write",
      shipmentKey: "staging-canary:vamo-place-intelligence-staging:approval:4",
      createdAt: "2026-06-28T12:00:00.000Z",
      approvalAuditId: "4"
    };
    const snapshot: ProgressiveRunSnapshot = {
      entries: sampleProgressiveRunSnapshot.entries.map((entry) =>
        entry.workStatus === "review_required" ? { ...entry, canaryShipment: shipment } : entry
      )
    };

    const view = buildProgressiveRunView(snapshot);
    const row = view.rows.find((r) => r.targetId === "vamo-place-intelligence-staging");
    assert.ok(row);
    // The proposal row is untouched (still review_required) but the ledger wins.
    assert.equal(row.workStatus, "review_required");
    assert.equal(row.canaryShipped, true);
    assert.equal(row.canaryShipment?.shipmentKey, shipment.shipmentKey);
    assert.match(row.nextApproval, /already shipped/i);
    assert.doesNotMatch(row.nextApproval, /approve/i);

    // The single next action no longer invites a repeat approval.
    assert.doesNotMatch(view.nextAction, /^Review vamo-place-intelligence-staging/);
    assert.match(view.nextAction, /already shipped to Vamo staging/i);
  });

  it("keeps review_required actionable when no active shipment exists", () => {
    const failed: CanaryShipmentState = {
      status: "failed",
      mode: "approved_write",
      shipmentKey: "staging-canary:vamo-place-intelligence-staging:approval:7",
      createdAt: "2026-06-28T12:00:00.000Z",
      approvalAuditId: "7"
    };
    const snapshot: ProgressiveRunSnapshot = {
      entries: sampleProgressiveRunSnapshot.entries.map((entry) =>
        entry.workStatus === "review_required" ? { ...entry, canaryShipment: failed } : entry
      )
    };

    const view = buildProgressiveRunView(snapshot);
    const row = view.rows.find((r) => r.targetId === "vamo-place-intelligence-staging");
    assert.ok(row);
    assert.equal(row.canaryShipped, false);
    assert.match(view.nextAction, /Review vamo-place-intelligence-staging/);
  });
});
