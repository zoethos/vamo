import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { buildBatchPlan } from "../src/batch-planner.js";
import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { sampleVamoEuPoiBatchPlan, sampleVamoEuPoiBatchYaml } from "../src/batch-plan-read-model.js";
import {
  buildBatchQueueSnapshot,
  buildBatchQueueSnapshotFromItems,
  formatBatchQueueBlockers,
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

  it("resolves consumer display fields on queue items", () => {
    const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
    const restaurant = snapshot.items.find(
      (item) => item.unitKey === "vamo-place-intelligence:barcelona-spain:restaurant"
    );

    assert.ok(restaurant);
    assert.deepEqual(restaurant.displayFields, [
      {
        key: "poi_type",
        label: "POI type",
        value: "Restaurant",
        detail: "feature_type=poi"
      }
    ]);
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

  it("counts lifecycle-blocked dry-run units as blocked next-action work", () => {
    const base = sampleVamoEuPoiBatchQueueSnapshot();
    const [first, second] = base.items;
    assert.ok(first && second);

    const snapshot = buildBatchQueueSnapshotFromItems({
      planId: base.planId,
      projectKey: base.projectKey,
      targetKey: base.targetKey,
      targetEnvironment: base.targetEnvironment,
      sourceKey: base.sourceKey,
      safetyMode: base.safetyMode,
      items: [
        {
          ...first,
          status: "dry_run_blocked",
          blockReasons: [
            "live_diff_noop: Current Vamo staging diff has no inserts or updates."
          ]
        },
        {
          ...second,
          status: "dry_run_blocked",
          blockReasons: [
            "no_fixture_candidates: No fixture candidates matched this scope."
          ]
        }
      ],
      planNextAction: "Review batch queue (36 ready for dry-run) and approve scheduling."
    });

    assert.equal(snapshot.progress.total, 2);
    assert.equal(snapshot.progress.blocked, 2);
    assert.equal(snapshot.progress.execution.dryRunBlocked, 2);
    assert.equal(snapshot.progress.ready, 0);
    assert.match(snapshot.nextAction, /Resolve 2 blocked unit/);
    assert.match(snapshot.nextAction, /live_diff_noop/);
  });

  it("describes parked empty source scopes without resolve wording", () => {
    const base = sampleVamoEuPoiBatchQueueSnapshot();
    const snapshot = buildBatchQueueSnapshotFromItems({
      planId: base.planId,
      projectKey: base.projectKey,
      targetKey: base.targetKey,
      targetEnvironment: base.targetEnvironment,
      sourceKey: base.sourceKey,
      safetyMode: base.safetyMode,
      items: base.items.map((item, index) =>
        index < 2
          ? {
              ...item,
              status: "blocked",
              blockReasons: ["source_snapshot_empty"]
            }
          : { ...item, status: "ready_for_dry_run", blockReasons: [] }
      ),
      planNextAction: "Review batch queue."
    });

    assert.match(
      snapshot.nextAction,
      /2 empty source scope\(s\) parked until snapshot coverage expands/
    );
    assert.doesNotMatch(snapshot.nextAction, /Resolve/i);
  });

  it("formats persisted JSON blocker objects for operators", () => {
    assert.deepEqual(
      formatBatchQueueBlockers([
        {
          code: "diff_drift",
          message: "Refusing to write: diff drifted from review."
        },
        { code: "live_diff_noop" },
        { message: "No fixture candidates matched this scope." }
      ]),
      [
        "diff_drift: Refusing to write: diff drifted from review.",
        "live_diff_noop",
        "No fixture candidates matched this scope."
      ]
    );
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
