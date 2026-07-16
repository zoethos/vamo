import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  extractPlanCommissionBounds,
  validateSnapshotCommissionScopeAgainstPlan
} from "../src/snapshot-commission-plan-context.js";

describe("extractPlanCommissionBounds", () => {
  it("derives allowed countries and categories from a batch plan spec", () => {
    const bounds = extractPlanCommissionBounds({
      kind: "ingestion.batch_plan",
      version: 1,
      id: "vamo-eu-poi-sample",
      projectKey: "vamo",
      sourceKey: "fsq-os-places-snapshot",
      targetProfileKey: "place-intelligence",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      safetyMode: "dry_run",
      geographies: {
        countries: [{ key: "italy" }, { key: "france" }],
        cities: [{ key: "rome-italy", country: "italy" }]
      },
      categories: ["poi", "landmark"],
      bounds: { sampleRowLimitPerUnit: 100 }
    });

    assert.deepEqual(bounds.allowedCountries, ["france", "italy"]);
    assert.deepEqual(bounds.allowedCategories, ["landmark", "poi"]);
    assert.equal(bounds.maxRowsPerScopeLimit, 100);
    assert.equal(bounds.sourceTaxonomy, null);
  });

  it("loads sourceTaxonomy when present on the plan contract", () => {
    const bounds = extractPlanCommissionBounds({
      kind: "ingestion.batch_plan",
      version: 1,
      id: "vamo-eu-full-data-v1",
      projectKey: "vamo",
      sourceKey: "fsq-os-places-snapshot",
      targetProfileKey: "place-intelligence",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      safetyMode: "dry_run",
      geographies: { countries: [{ key: "italy" }] },
      categories: ["poi"],
      bounds: { sampleRowLimitPerUnit: 100 },
      sourceTaxonomy: {
        provider: "fsq_os_places",
        fallbackConsumerCategory: "poi",
        mappings: [
          {
            providerCategoryIds: ["museum-id"],
            providerCategoryLabels: ["Museum"],
            consumerCategory: "landmark",
            precedence: 10
          }
        ]
      }
    });
    assert.ok(bounds.sourceTaxonomy);
    assert.equal(bounds.sourceTaxonomy?.fallbackConsumerCategory, "poi");
  });
});

describe("validateSnapshotCommissionScopeAgainstPlan", () => {
  const plan = {
    projectKey: "vamo",
    planKey: "vamo-eu-poi-sample",
    sourceKey: "fsq-os-places-snapshot",
    planStatus: "active",
    allowedCountries: ["italy", "france"],
    allowedCategories: ["poi", "landmark"],
    maxRowsPerScopeLimit: 100,
    sourceTaxonomy: null
  };

  it("accepts scope inside plan and FSQ bounds", () => {
    const decision = validateSnapshotCommissionScopeAgainstPlan({
      countries: ["italy"],
      categories: ["poi"],
      maxRowsPerScope: 50,
      plan
    });
    assert.equal(decision.ok, true);
  });

  it("rejects countries outside the plan contract", () => {
    const decision = validateSnapshotCommissionScopeAgainstPlan({
      countries: ["germany"],
      categories: ["poi"],
      maxRowsPerScope: 50,
      plan
    });
    assert.equal(decision.ok, false);
    if (decision.ok) return;
    assert.equal(decision.code, "scope_out_of_bounds");
  });
});
