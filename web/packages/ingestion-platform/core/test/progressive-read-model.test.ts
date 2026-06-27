import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  buildProgressiveRunView,
  sampleProgressiveRunSnapshot,
  sampleVamoProposal
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

    // Progress, checkpoint, and shipment diff are visible.
    assert.equal(vamo!.rowsRead, 5);
    assert.equal(vamo!.rowsStaged, 3);
    assert.match(vamo!.checkpoint, /source_row_id=/);
    assert.match(vamo!.shipmentDiff, /insert/);
    assert.ok(vamo!.policyBlocks.length >= 1);
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
});
