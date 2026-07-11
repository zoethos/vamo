import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import {
  buildBatchFullDataPlanPreview,
  resolveUnitVolume
} from "../src/batch-full-data-plan-preview.js";
import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { buildBatchPlan } from "../src/batch-planner.js";
import { vamoEuFullDataBatchPlan } from "../src/batch-plan-read-model.js";
import { buildBatchQueueSnapshotFromPlan } from "../src/batch-queue-read-model.js";

const fullDataPath = "fixtures/platform/ip18/vamo-eu-full-data-batch.yaml";

describe("full-data batch plan preview", () => {
  it("parses and expands the bundled Vamo EU full-data spec", () => {
    const parsed = parseBatchPlanSpec(readFileSync(fullDataPath, "utf8"));
    assert.equal(parsed.ok, true);
    if (!parsed.ok) {
      return;
    }
    assert.equal(parsed.spec.id, "vamo-eu-full-data-v1");
    assert.equal(parsed.spec.sourceKey, "fsq-os-places-snapshot");
    assert.equal(parsed.spec.consumerContractRef, "vamo-place-intelligence");
    assert.equal(parsed.spec.source?.adapter, "snapshot");
    assert.ok(parsed.spec.volumeProjection?.byCategory?.poi);
  });

  it("expands full-data coverage deterministically with stable unit keys", () => {
    const first = vamoEuFullDataBatchPlan();
    const second = vamoEuFullDataBatchPlan();
    assert.deepEqual(
      first.units.map((unit) => unit.unitKey),
      second.units.map((unit) => unit.unitKey)
    );
    assert.equal(first.totalUnits, 168);
    assert.equal(first.plannedUnits, 168);
    assert.equal(first.targetEnvironment, "staging");
    assert.ok(!first.targetKey.includes("-staging"));
    assert.equal(first.units[0]?.unitKey, "vamo-place-intelligence:rome-italy:poi");
  });

  it("summarizes source candidates separately from expected target writes", () => {
    const parsed = parseBatchPlanSpec(readFileSync(fullDataPath, "utf8"));
    assert.equal(parsed.ok, true);
    if (!parsed.ok) {
      return;
    }
    const preview = buildBatchFullDataPlanPreview({ spec: parsed.spec });
    assert.equal(preview.queueUnitCount, 168);
    assert.equal(preview.volume.totalSourceCandidates, 756_000);
    assert.equal(preview.volume.totalExpectedTargetWrites, 697_200);
    assert.equal(preview.volume.perCategory.poi?.displayLabel, "General");
    assert.equal(preview.volume.perCategory.restaurant?.displayLabel, "Restaurant");
    assert.ok(preview.volume.totalSourceCandidates > preview.volume.totalExpectedTargetWrites);
    assert.equal(preview.volume.perCategory.poi?.sourceCandidates, 336_000);
    assert.equal(preview.volume.perCategory.poi?.expectedTargetWrites, 302_400);
  });

  it("builds a coverage matrix by country and POI category", () => {
    const preview = buildBatchFullDataPlanPreview({
      spec: loadFullDataSpec()
    });
    assert.equal(Object.keys(preview.coverageMatrix).length, 12);
    assert.equal(preview.coverageMatrix.italy?.poi, 4);
    assert.equal(preview.coverage.perCategory.poi, 42);
    assert.equal(preview.coverage.perCountry.italy, 16);
  });

  it("resolves queue display labels through the consumer contract presenter path", () => {
    const plan = vamoEuFullDataBatchPlan();
    const snapshot = buildBatchQueueSnapshotFromPlan(plan);
    const transport = snapshot.items.find(
      (item) => item.unitKey === "vamo-place-intelligence:berlin-germany:transport"
    );
    assert.ok(transport);
    assert.deepEqual(transport.displayFields, [
      {
        key: "poi_type",
        label: "POI type",
        value: "Transport",
        detail: "feature_type=poi"
      }
    ]);
    assert.equal(transport.targetEnvironment, "staging");
  });

  it("rejects URL, live, and evasion source controls in the batch spec", () => {
    for (const sourceKey of ["https://example.com/places", "google-places-live"]) {
      const parsed = parseBatchPlanSpec({
        kind: "ingestion.batch_plan",
        version: 1,
        id: "unsafe-source",
        projectKey: "vamo",
        sourceKey,
        targetProfileKey: "place-intelligence",
        targetKey: "vamo-place-intelligence",
        targetEnvironment: "staging",
        safetyMode: "dry_run",
        geographies: { countries: [{ key: "italy" }] },
        categories: ["poi"]
      });
      assert.equal(parsed.ok, false, `expected ${sourceKey} to fail`);
      if (parsed.ok) {
        continue;
      }
      assert.ok(parsed.errors.some((error) => error.code === "unsafe_source_connection"));
    }

    const evasion = parseBatchPlanSpec({
      kind: "ingestion.batch_plan",
      version: 1,
      id: "unsafe-connection",
      projectKey: "vamo",
      sourceKey: "fsq-os-places-snapshot",
      targetProfileKey: "place-intelligence",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      safetyMode: "dry_run",
      source: {
        adapter: "snapshot",
        connection: {
          snapshotPath: "https://example.com/places.jsonl",
          proxy: "socks5://127.0.0.1:9050"
        }
      },
      geographies: { countries: [{ key: "italy" }] },
      categories: ["poi"]
    });
    assert.equal(evasion.ok, false);
    if (evasion.ok) {
      return;
    }
    assert.ok(evasion.errors.some((error) => error.path.includes("proxy")));
    assert.ok(evasion.errors.some((error) => error.path.includes("snapshotPath")));

    const malformedConnection = parseBatchPlanSpec({
      kind: "ingestion.batch_plan",
      version: 1,
      id: "malformed-connection",
      projectKey: "vamo",
      sourceKey: "fsq-os-places-snapshot",
      targetProfileKey: "place-intelligence",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      safetyMode: "dry_run",
      source: {
        adapter: "snapshot",
        connection: "https://example.com/places.jsonl"
      },
      geographies: { countries: [{ key: "italy" }] },
      categories: ["poi"]
    });
    assert.equal(malformedConnection.ok, false);
    if (malformedConnection.ok) {
      return;
    }
    assert.ok(
      malformedConnection.errors.some((error) => error.path === "source.connection")
    );
  });

  it("keeps category volume overrides explicit per unit category", () => {
    const spec = loadFullDataSpec();
    assert.equal(resolveUnitVolume(spec, "poi").sourceCandidates, 8000);
    assert.equal(resolveUnitVolume(spec, "poi").expectedTargetWrites, 7200);
    assert.equal(resolveUnitVolume(spec, "landmark").sourceCandidates, 2500);
    assert.equal(resolveUnitVolume(spec, "transport").expectedTargetWrites, 1500);
  });

  it("orders units by priority then stable unit key", () => {
    const plan = buildBatchPlan({ spec: loadFullDataSpec() });
    const keys = plan.units.map((unit) => unit.unitKey);
    assert.deepEqual(keys, [...keys].sort((left, right) => {
      const leftUnit = plan.units.find((unit) => unit.unitKey === left)!;
      const rightUnit = plan.units.find((unit) => unit.unitKey === right)!;
      if (rightUnit.priority !== leftUnit.priority) {
        return rightUnit.priority - leftUnit.priority;
      }
      return left.localeCompare(right);
    }));
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
