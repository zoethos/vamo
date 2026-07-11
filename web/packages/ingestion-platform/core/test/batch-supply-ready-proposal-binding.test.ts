import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { buildBatchPlan } from "../src/batch-planner.js";
import { sampleVamoEuPoiBatchQueueSnapshot } from "../src/batch-queue-read-model.js";
import { mapSnapshotToPersistenceBundle } from "../src/batch-queue-persistence.js";
import {
  BATCH_SNAPSHOT_EMPTY_BLOCK_REASON,
  buildBatchSnapshotSupplyPreview,
  readSnapshotSourceRowsFromSpec
} from "../src/batch-snapshot-supply-preview.js";
import {
  bindSupplyReadyScheduleProposals,
  buildFullDataBoundBatchQueueSnapshot,
  readProposalQuotaMaxRows,
  readProposalRowLimit
} from "../src/batch-supply-ready-proposal-binding.js";

const fullDataPath = "fixtures/platform/ip18/vamo-eu-full-data-batch.yaml";

describe("batch supply-ready proposal binding", () => {
  it("creates 36 proposal-backed ready_for_dry_run units and 132 blocked empty units", () => {
    const spec = loadFullDataSpec();
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const { snapshot, plan } = buildFullDataBoundBatchQueueSnapshot({ spec, rows });

    assert.equal(snapshot.progress.total, 168);
    assert.equal(snapshot.progress.ready, 36);
    assert.equal(snapshot.progress.blocked, 132);
    assert.equal(plan.units.filter((unit) => unit.proposal).length, 36);

    const readyItems = snapshot.items.filter((item) => item.status === "ready_for_dry_run");
    assert.equal(readyItems.length, 36);
    assert.ok(readyItems.every((item) => item.proposal));
    assert.ok(
      snapshot.items
        .filter((item) => item.blockReasons.includes(BATCH_SNAPSHOT_EMPTY_BLOCK_REASON))
        .every((item) => item.status === "blocked" && !item.proposal)
    );
  });

  it("bounds proposal row limits by valid local snapshot rows, not projected volume", () => {
    const spec = loadFullDataSpec();
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const { plan, supplyPreview } = buildFullDataBoundBatchQueueSnapshot({ spec, rows });
    const romePoi = plan.units.find(
      (unit) => unit.unitKey === "vamo-place-intelligence:rome-italy:poi"
    );
    const supply = supplyPreview.supplyReadyUnits.find(
      (unit) => unit.unitKey === "vamo-place-intelligence:rome-italy:poi"
    );

    assert.ok(romePoi?.proposal);
    assert.ok(supply);
    assert.equal(supply.validSourceRowCount, 2);
    assert.equal(readProposalRowLimit(romePoi.proposal), 2);
    assert.equal(readProposalQuotaMaxRows(romePoi.proposal), 2);
    assert.ok(readProposalRowLimit(romePoi.proposal)! < 5000);
    assert.equal(romePoi.proposal?.safetyMode, "dry_run");
  });

  it("persists proposals for supply-ready units and clears proposals for blocked empty units", () => {
    const spec = loadFullDataSpec();
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const { snapshot } = buildFullDataBoundBatchQueueSnapshot({ spec, rows });
    const bundle = mapSnapshotToPersistenceBundle(snapshot, spec);

    const ready = bundle.items.filter((item) => item.status === "ready_for_dry_run");
    const blocked = bundle.items.filter((item) => item.status === "blocked");
    assert.equal(ready.length, 36);
    assert.equal(blocked.length, 132);
    assert.ok(ready.every((item) => item.proposal));
    assert.ok(blocked.every((item) => item.proposal === null));
  });

  it("clears stale proposals when a previously ready unit becomes empty on re-seed", () => {
    const spec = loadFullDataSpec();
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const first = buildFullDataBoundBatchQueueSnapshot({ spec, rows });
    const romeKey = "vamo-place-intelligence:rome-italy:poi";
    const firstRome = first.snapshot.items.find((item) => item.unitKey === romeKey);
    assert.ok(firstRome?.proposal);
    assert.equal(firstRome.status, "ready_for_dry_run");

    const rowsWithoutRome = rows.filter(
      (row) => row.scope?.geography !== "rome-italy" || row.scope?.category !== "poi"
    );
    const second = buildFullDataBoundBatchQueueSnapshot({ spec, rows: rowsWithoutRome });
    const secondRome = second.snapshot.items.find((item) => item.unitKey === romeKey);
    assert.ok(secondRome);
    assert.equal(secondRome.status, "blocked");
    assert.equal(secondRome.proposal, null);
    assert.ok(secondRome.blockReasons.includes(BATCH_SNAPSHOT_EMPTY_BLOCK_REASON));
  });

  it("does not attach proposals to empty or invalid units", () => {
    const spec = loadFullDataSpec();
    const plan = buildBatchPlan({ spec });
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const supplyPreview = buildBatchSnapshotSupplyPreview({ plan, spec, rows });
    const bound = bindSupplyReadyScheduleProposals({ spec, plan, supplyPreview });

    for (const unit of bound.units) {
      const supply = supplyPreview.perUnit.find((entry) => entry.unitKey === unit.unitKey);
      assert.ok(supply);
      if (supply.supplyState === "supply_ready") {
        assert.ok(unit.proposal);
      } else {
        assert.equal(unit.proposal, undefined);
      }
    }
  });

  it("leaves the sample POI batch behavior unchanged", () => {
    const sample = sampleVamoEuPoiBatchQueueSnapshot();
    assert.equal(sample.progress.total, 36);
    assert.equal(sample.progress.blocked, 0);
    assert.equal(sample.progress.ready, 36);
  });
});

function loadFullDataSpec() {
  const parsed = parseBatchPlanSpec(readFileSync(fullDataPath, "utf8"));
  assert.equal(parsed.ok, true);
  if (!parsed.ok) {
    throw new Error("full-data spec failed to parse");
  }
  assert.ok(parsed.spec.dryRunProposalFacts?.sourceRights?.liveOnly === false);
  return parsed.spec;
}
