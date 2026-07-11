import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";

const samplePath = "fixtures/platform/ip18/vamo-eu-poi-batch.yaml";

describe("batch plan spec parser", () => {
  it("parses the bundled Vamo EU POI sample", () => {
    const parsed = parseBatchPlanSpec(readFileSync(samplePath, "utf8"));
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.spec.kind, "ingestion.batch_plan");
    assert.equal(parsed.spec.projectKey, "vamo");
    assert.equal(parsed.spec.targetKey, "vamo-place-intelligence");
    assert.equal(parsed.spec.targetEnvironment, "staging");
    assert.equal(parsed.spec.safetyMode, "dry_run");
    assert.ok(parsed.spec.categories.length >= 4);
    assert.ok(hasAnyGeography(parsed.spec.geographies));
  });

  it("rejects production_write and other non-dry-run modes", () => {
    for (const safetyMode of ["staging_write", "production_write", "approved_write"]) {
      const parsed = parseBatchPlanSpec({
        kind: "ingestion.batch_plan",
        version: 1,
        id: "unsafe",
        projectKey: "vamo",
        sourceKey: "fsq-os-places-sample",
        targetProfileKey: "place-intelligence",
        targetKey: "vamo-place-intelligence",
        targetEnvironment: "staging",
        safetyMode,
        geographies: { countries: [{ key: "italy" }] },
        categories: ["poi"]
      });
      assert.equal(parsed.ok, false, `expected ${safetyMode} to fail`);
      if (parsed.ok) continue;
      assert.ok(parsed.errors.some((error) => error.code === "unsafe_safety_mode"));
    }
  });

  it("rejects legacy environment-encoded target keys", () => {
    const parsed = parseBatchPlanSpec({
      kind: "ingestion.batch_plan",
      version: 1,
      id: "legacy",
      projectKey: "vamo",
      sourceKey: "fsq-os-places-sample",
      targetProfileKey: "place-intelligence",
      targetKey: "vamo-place-intelligence-staging",
      targetEnvironment: "staging",
      safetyMode: "dry_run",
      geographies: { countries: [{ key: "italy" }] },
      categories: ["poi"]
    });
    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.ok(parsed.errors.some((error) => error.code === "legacy_target_key"));
  });

  it("requires explicit geography and category scope", () => {
    const parsed = parseBatchPlanSpec({
      kind: "ingestion.batch_plan",
      version: 1,
      id: "empty",
      projectKey: "vamo",
      sourceKey: "fsq-os-places-sample",
      targetProfileKey: "place-intelligence",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      safetyMode: "dry_run",
      geographies: {},
      categories: []
    });
    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.ok(parsed.errors.some((error) => error.code === "empty_scope"));
  });

  it("parses the bundled Vamo EU full-data plan with volume projection", () => {
    const parsed = parseBatchPlanSpec(
      readFileSync("fixtures/platform/ip18/vamo-eu-full-data-batch.yaml", "utf8")
    );
    assert.equal(parsed.ok, true);
    if (parsed.ok) {
      assert.equal(parsed.spec.volumeProjection?.byCategory?.restaurant?.sourceCandidatesPerUnit, 6000);
      assert.equal(parsed.spec.source?.connection?.snapshotPath, "fixtures/imported/vamo-place-intelligence/fixtures/source.jsonl");
    }
  });

  it("validates dry-run proposal fact booleans and collision policy", () => {
    const parsed = parseBatchPlanSpec({
      kind: "ingestion.batch_plan",
      version: 1,
      id: "bad-proposal-facts",
      projectKey: "vamo",
      sourceKey: "fsq-os-places-snapshot",
      targetProfileKey: "place-intelligence",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      safetyMode: "dry_run",
      geographies: { countries: [{ key: "italy" }] },
      categories: ["poi"],
      dryRunProposalFacts: {
        sourceRights: {
          canStoreFacts: "yes"
        },
        collision: {
          policy: "fast"
        }
      }
    });

    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.ok(
      parsed.errors.some(
        (error) =>
          error.code === "invalid_shape" &&
          error.path === "dryRunProposalFacts.sourceRights.canStoreFacts"
      )
    );
    assert.ok(
      parsed.errors.some(
        (error) =>
          error.code === "invalid_shape" &&
          error.path === "dryRunProposalFacts.collision.policy"
      )
    );
  });
});

function hasAnyGeography(geographies: {
  countries?: unknown[];
  regions?: unknown[];
  cities?: unknown[];
  areas?: unknown[];
  boundingBoxes?: unknown[];
}): boolean {
  return Boolean(
    geographies.countries?.length ||
      geographies.regions?.length ||
      geographies.cities?.length ||
      geographies.areas?.length ||
      geographies.boundingBoxes?.length
  );
}
