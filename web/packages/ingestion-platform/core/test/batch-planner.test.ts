import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { buildBatchPlan } from "../src/batch-planner.js";
import type { TargetCandidateInput } from "../src/target-scorecard.js";

const samplePath = "fixtures/platform/ip18/vamo-eu-poi-batch.yaml";

const candidateTemplate: TargetCandidateInput = {
  targetId: "vamo-place-intelligence",
  projectKey: "vamo",
  sourceId: "fsq-os-places-sample",
  safetyMode: "dry_run",
  consumerValue: { useCase: "EU POI cache seeding.", reducesLiveCalls: true },
  sourceRights: {
    canStoreFacts: true,
    attributionPresent: true,
    retentionDeclared: true,
    liveOnly: false
  },
  targetReadiness: {
    schemaCompatible: true,
    upsertKeysDeclared: true,
    rlsPostureOk: true,
    stagingEnvironmentExists: true
  },
  dataQuality: { requiredFieldsPresent: true, coordinatesValid: true, sampleRowCount: 3 },
  checkpointability: { cursorStrategyDeclared: true, resumeTested: true },
  costAndQuota: { rowLimitDeclared: true, stopConditionsDeclared: true, withinBudget: true },
  collision: { policy: "review" },
  blastRadius: { bounded: true, firstShipmentStagingOnly: true },
  observability: {
    eventsAvailable: true,
    checkpointsAvailable: true,
    deadLettersAvailable: true,
    statsAvailable: true
  }
};

describe("batch planner", () => {
  it("expands the Vamo EU POI sample deterministically", () => {
    const spec = loadSampleSpec();
    const first = buildBatchPlan({ spec, candidateTemplate });
    const second = buildBatchPlan({ spec, candidateTemplate });
    assert.deepEqual(first, second);
    assert.ok(first.totalUnits > 0);
    assert.equal(first.plannedUnits, first.totalUnits);
    assert.equal(first.blockedUnits, 0);
    assert.equal(first.targetKey, "vamo-place-intelligence");
    assert.ok(!first.units.some((unit) => unit.targetId.includes("-staging")));
  });

  it("deduplicates geography/category combinations", () => {
    const spec = loadSampleSpec();
    spec.geographies.cities = [
      ...(spec.geographies.cities ?? []),
      { key: "rome-italy", country: "italy", label: "Rome duplicate" }
    ];
    const plan = buildBatchPlan({ spec, candidateTemplate });
    const keys = new Set(plan.units.map((unit) => `${unit.geography}:${unit.category}`));
    assert.equal(keys.size, plan.units.length);
  });

  it("blocks units when source config is stripped from a custom spec", () => {
    const spec = loadSampleSpec();
    spec.sourceKey = "";
    const plan = buildBatchPlan({ spec });
    assert.ok(plan.blockedUnits > 0);
    assert.ok(plan.units.every((unit) => unit.status === "blocked"));
    assert.ok(plan.units[0]?.blockReasons.includes("missing_source_key"));
  });

  it("throws when asked to plan a non-dry-run spec", () => {
    const spec = loadSampleSpec();
    spec.safetyMode = "production_write";
    assert.throws(() => buildBatchPlan({ spec }), /requires safetyMode=dry_run/);
  });

  it("orders Rome POI ahead of lower-priority units", () => {
    const plan = buildBatchPlan({ spec: loadSampleSpec(), candidateTemplate });
    const romePoi = plan.units.find(
      (unit) => unit.geography === "rome-italy" && unit.category === "poi"
    );
    assert.ok(romePoi);
    assert.equal(romePoi.priority, 10);
    assert.equal(plan.units[0]?.unitKey, romePoi.unitKey);
  });

  it("attaches schedule proposals for planned units", () => {
    const plan = buildBatchPlan({ spec: loadSampleSpec(), candidateTemplate });
    const withProposal = plan.units.filter((unit) => unit.proposal);
    assert.ok(withProposal.length > 0);
    assert.equal(withProposal[0]?.proposal?.safetyMode, "dry_run");
    assert.equal(withProposal[0]?.proposal?.targetId, "vamo-place-intelligence");
  });
});

function loadSampleSpec() {
  const parsed = parseBatchPlanSpec(readFileSync(samplePath, "utf8"));
  assert.equal(parsed.ok, true);
  if (!parsed.ok) {
    throw new Error("sample spec failed to parse");
  }
  return parsed.spec;
}
