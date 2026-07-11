import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { buildBatchPlan } from "../src/batch-planner.js";
import { sampleVamoEuPoiBatchQueueSnapshot, buildBatchQueueSnapshotFromPlan } from "../src/batch-queue-read-model.js";
import { mapSnapshotToPersistenceBundle } from "../src/batch-queue-persistence.js";
import {
  applySnapshotSupplyToQueueSnapshot,
  BATCH_SNAPSHOT_EMPTY_BLOCK_REASON,
  buildBatchQueueSnapshotWithSupplyBinding,
  buildBatchSnapshotSupplyPreview,
  readSnapshotSourceRowsFromSpec
} from "../src/batch-snapshot-supply-preview.js";

const fullDataPath = "fixtures/platform/ip18/vamo-eu-full-data-batch.yaml";
const samplePath = "fixtures/platform/ip18/vamo-eu-poi-batch.yaml";

describe("batch snapshot supply preview", () => {
  it("returns bundled snapshot supply counts for the full-data plan", () => {
    const spec = loadFullDataSpec();
    const plan = buildBatchPlan({ spec });
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const preview = buildBatchSnapshotSupplyPreview({ plan, spec, rows });

    assert.equal(preview.summary.actualSourceRows, 38);
    assert.equal(preview.summary.unitsWithSourceRows, 36);
    assert.equal(preview.summary.unitsWithoutSourceRows, 132);
    assert.equal(preview.summary.totalPlannedUnits, 168);
    assert.ok(Object.keys(preview.summary.rowsByCountry).length >= 4);
    assert.ok(preview.summary.rowsByCategory.poi >= 1);
  });

  it("marks empty units blocked by default in the full-data seed path", () => {
    const spec = loadFullDataSpec();
    const plan = buildBatchPlan({ spec });
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const { snapshot } = buildBatchQueueSnapshotWithSupplyBinding({ plan, spec, rows });

    assert.equal(snapshot.progress.total, 168);
    assert.equal(snapshot.progress.blocked, 132);
    assert.equal(snapshot.progress.ready, 0);
    assert.ok(
      snapshot.items.every(
        (item) =>
          item.status !== "ready_for_dry_run" && item.status !== "dry_run_ready"
      )
    );

    const emptyItem = snapshot.items.find(
      (item) => item.unitKey === "vamo-place-intelligence:portugal:poi"
    );
    assert.ok(emptyItem);
    assert.equal(emptyItem.status, "blocked");
    assert.ok(emptyItem.blockReasons.includes(BATCH_SNAPSHOT_EMPTY_BLOCK_REASON));

    const readyScopeItem = snapshot.items.find(
      (item) => item.unitKey === "vamo-place-intelligence:rome-italy:poi"
    );
    assert.ok(readyScopeItem);
    assert.notEqual(readyScopeItem.status, "blocked");
  });

  it("can include empty units when seed mode explicitly opts in", () => {
    const spec = loadFullDataSpec();
    const plan = buildBatchPlan({ spec });
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const base = buildBatchQueueSnapshotFromPlan(plan);
    const supplyPreview = buildBatchSnapshotSupplyPreview({ plan, spec, rows });
    const included = applySnapshotSupplyToQueueSnapshot({
      snapshot: base,
      supplyPreview,
      seedMode: "include_empty_units"
    });

    const emptyItem = included.items.find(
      (item) => item.unitKey === "vamo-place-intelligence:portugal:poi"
    );
    assert.ok(emptyItem);
    assert.notEqual(emptyItem.status, "blocked");
    assert.equal(emptyItem.blockReasons.includes(BATCH_SNAPSHOT_EMPTY_BLOCK_REASON), false);
  });

  it("persists blocked empty units in the control-plane bundle", () => {
    const spec = loadFullDataSpec();
    const plan = buildBatchPlan({ spec });
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const { snapshot } = buildBatchQueueSnapshotWithSupplyBinding({ plan, spec, rows });
    const bundle = mapSnapshotToPersistenceBundle(snapshot, spec);

    assert.equal(bundle.items.length, 168);
    const blocked = bundle.items.filter((item) => item.status === "blocked");
    assert.equal(blocked.length, 132);
    assert.ok(
      blocked.every((item) => item.blockers.includes(BATCH_SNAPSHOT_EMPTY_BLOCK_REASON))
    );
  });

  it("leaves the sample POI batch seed behavior unchanged", () => {
    const sample = sampleVamoEuPoiBatchQueueSnapshot();
    assert.equal(sample.progress.total, 36);
    assert.equal(sample.progress.blocked, 0);
    assert.equal(sample.progress.ready, 36);
  });

  it("does not read snapshot supply for specs without a local snapshot path", () => {
    const parsed = parseBatchPlanSpec(readFileSync(samplePath, "utf8"));
    assert.equal(parsed.ok, true);
    if (!parsed.ok) {
      return;
    }
    assert.equal(readSnapshotSourceRowsFromSpec(parsed.spec), undefined);
  });
});

function loadFullDataSpec() {
  const parsed = parseBatchPlanSpec(readFileSync(fullDataPath, "utf8"));
  assert.equal(parsed.ok, true);
  if (!parsed.ok) {
    throw new Error("full-data spec failed to parse");
  }
  return parsed.spec;
}
