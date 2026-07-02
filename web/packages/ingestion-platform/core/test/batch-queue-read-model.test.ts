import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { buildBatchPlan } from "../src/batch-planner.js";
import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { sampleVamoEuPoiBatchPlan, sampleVamoEuPoiBatchYaml } from "../src/batch-plan-read-model.js";
import {
  buildBatchQueueSnapshot,
  sampleVamoEuPoiBatchQueueSnapshot
} from "../src/batch-queue-read-model.js";

describe("batch queue read model", () => {
  it("groups the Vamo sample deterministically by country", () => {
    const first = sampleVamoEuPoiBatchQueueSnapshot();
    const second = sampleVamoEuPoiBatchQueueSnapshot();
    assert.deepEqual(first, second);
    assert.equal(first.progress.total, 36);
    assert.equal(first.targetKey, "vamo-place-intelligence");
    assert.ok(!first.targetKey.includes("-staging"));
    assert.equal(first.groups.length, 4);
    assert.deepEqual(
      first.groups.map((group) => group.groupKey).sort(),
      ["france", "germany", "italy", "spain"]
    );
    assert.equal(first.items.length, 36);
    assert.equal(first.items[0]?.unitKey, "vamo-place-intelligence:rome-italy:poi");
  });

  it("reports coverage counts for 36 planned-or-ready units", () => {
    const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
    assert.equal(snapshot.progress.total, 36);
    assert.equal(snapshot.progress.blocked, 0);
    assert.equal(snapshot.progress.ready, 36);
    assert.equal(snapshot.coverage.perCountry.italy, 12);
    assert.equal(snapshot.coverage.perCountry.france, 8);
    assert.equal(snapshot.coverage.perCountry.germany, 8);
    assert.equal(snapshot.coverage.perCountry.spain, 8);
    assert.equal(snapshot.coverage.perCategory.poi, 9);
    assert.equal(snapshot.coverage.perSource["fsq-os-places-sample"], 36);
    assert.equal(snapshot.coverage.matrix.italy?.poi, 3);
  });

  it("surfaces blocker summaries when scope is invalid", () => {
    const parsed = parseBatchPlanSpec(sampleVamoEuPoiBatchYaml());
    assert.equal(parsed.ok, true);
    if (!parsed.ok) {
      throw new Error("sample yaml failed to parse");
    }
    const spec = parsed.spec;
    spec.sourceKey = "";
    const plan = buildBatchPlan({ spec });
    const snapshot = buildBatchQueueSnapshot({ plan });
    assert.equal(snapshot.progress.blocked, 36);
    assert.equal(snapshot.progress.ready, 0);
    assert.ok(snapshot.blockerSummaries.some((entry) => entry.reason === "missing_source_key"));
    assert.match(snapshot.nextAction, /blocked unit/i);
  });

  it("keeps applied/progress math stable with progression overrides", () => {
    const plan = sampleVamoEuPoiBatchPlan();
    const [firstUnit, secondUnit] = plan.units;
    assert.ok(firstUnit && secondUnit);
    const snapshot = buildBatchQueueSnapshot({
      plan,
      progressionByUnitKey: {
        [firstUnit.unitKey]: "applied",
        [secondUnit.unitKey]: "dry_run_ready"
      }
    });
    assert.equal(snapshot.progress.applied, 1);
    assert.equal(snapshot.progress.ready, 35);
    assert.equal(snapshot.progress.planned, 0);
    assert.equal(snapshot.progress.blocked, 0);
    const italyGroup = snapshot.groups.find((group) => group.groupKey === "italy");
    assert.ok(italyGroup);
    assert.equal(italyGroup.appliedUnits, 1);
  });

  it("never emits environment-encoded target keys on queue items", () => {
    const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
    for (const item of snapshot.items) {
      assert.equal(item.targetKey, "vamo-place-intelligence");
      assert.ok(!item.targetKey.endsWith("-staging"));
      assert.ok(!item.targetKey.endsWith("-production"));
      assert.equal(item.targetEnvironment, "staging");
    }
  });
});
