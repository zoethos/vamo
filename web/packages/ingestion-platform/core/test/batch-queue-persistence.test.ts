import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import {
  assertValidQueueItemStatus,
  mapPersistenceBundleToSnapshot,
  mapSnapshotToPersistenceBundle
} from "../src/batch-queue-persistence.js";
import { sampleVamoEuPoiBatchYaml } from "../src/batch-plan-read-model.js";
import { sampleVamoEuPoiBatchQueueSnapshot } from "../src/batch-queue-read-model.js";

describe("batch queue persistence mapper", () => {
  it("round-trips the Vamo sample snapshot with stable coverage and matrix", () => {
    const original = sampleVamoEuPoiBatchQueueSnapshot();
    const parsed = parseBatchPlanSpec(sampleVamoEuPoiBatchYaml());
    assert.equal(parsed.ok, true);
    if (!parsed.ok) {
      throw new Error("sample yaml failed to parse");
    }

    const bundle = mapSnapshotToPersistenceBundle(original, parsed.spec);
    const roundTripped = mapPersistenceBundleToSnapshot(original.projectKey, bundle.plan, bundle.items);

    assert.equal(roundTripped.progress.total, 36);
    assert.equal(roundTripped.targetKey, "vamo-place-intelligence");
    assert.equal(roundTripped.targetEnvironment, "staging");
    assert.deepEqual(roundTripped.coverage.perCountry, original.coverage.perCountry);
    assert.deepEqual(roundTripped.coverage.perCategory, original.coverage.perCategory);
    assert.deepEqual(roundTripped.coverage.matrix, original.coverage.matrix);
    assert.deepEqual(
      roundTripped.items.map((item) => item.status),
      original.items.map((item) => item.status)
    );
    assert.deepEqual(
      roundTripped.items.map((item) => item.blockReasons),
      original.items.map((item) => item.blockReasons)
    );
    assert.ok(!roundTripped.targetKey.includes("-staging"));
  });

  it("rejects invalid queue item statuses", () => {
    assert.throws(() => assertValidQueueItemStatus("shipping"), /Invalid batch queue item status/);
  });

  it("enriches a live snapshot with prior-plan package evidence without persisting it", () => {
    const original = sampleVamoEuPoiBatchQueueSnapshot();
    const parsed = parseBatchPlanSpec(sampleVamoEuPoiBatchYaml());
    assert.equal(parsed.ok, true);
    if (!parsed.ok) {
      throw new Error("sample yaml failed to parse");
    }

    const bundle = mapSnapshotToPersistenceBundle(original, parsed.spec);
    const unitKey = original.items[0]!.unitKey;
    const enriched = mapPersistenceBundleToSnapshot(original.projectKey, bundle.plan, bundle.items, null, null, null, {
      crossPlanPackageLifecycleByUnitKey: {
        [unitKey]: {
          planKey: "vamo-eu-poi-sample",
          waveKey: "batch-production-inbox:vamo-eu-poi-sample:wave:58:unit:test",
          status: "consumer_applied"
        }
      }
    });

    assert.deepEqual(enriched.items[0]?.crossPlanPackageLifecycle, {
      planKey: "vamo-eu-poi-sample",
      waveKey: "batch-production-inbox:vamo-eu-poi-sample:wave:58:unit:test",
      status: "consumer_applied"
    });
    assert.equal(bundle.items[0]?.proposal, null);
    assert.equal("crossPlanPackageLifecycle" in bundle.items[0]!, false);
  });
});
