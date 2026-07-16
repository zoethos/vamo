import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  assessFsqRequestedCoverage,
  buildFsqCategoryCoveragePlan,
  formatFsqRequestedCoverageAssessment,
  providerCategoryIdsForConsumerCategory
} from "../src/fsq-category-coverage-plan.js";
import type { FsqSourceTaxonomyMapping } from "../src/fsq-source-taxonomy.js";

const taxonomy: FsqSourceTaxonomyMapping = {
  provider: "fsq_os_places",
  fallbackConsumerCategory: "poi",
  mappings: [
    {
      providerCategoryIds: ["museum-id", "landmark-id"],
      providerCategoryLabels: ["Museum"],
      consumerCategory: "landmark",
      precedence: 100
    },
    {
      providerCategoryIds: ["restaurant-id"],
      providerCategoryLabels: ["Restaurant"],
      consumerCategory: "restaurant",
      precedence: 90
    },
    {
      providerCategoryIds: [],
      providerCategoryLabels: ["Generic place"],
      consumerCategory: "poi",
      precedence: 10
    }
  ]
};

describe("fsq category coverage plan", () => {
  it("builds one query scope per country and POI type with explicit provider IDs", () => {
    const plan = buildFsqCategoryCoveragePlan({
      countries: ["italy"],
      categories: ["landmark", "restaurant"],
      maxRowsPerScope: 25,
      sourceTaxonomy: taxonomy
    });
    assert.equal(plan.ok, true);
    if (!plan.ok) return;
    assert.deepEqual(
      plan.plan.scopes.map((scope) => ({
        country: scope.country,
        category: scope.consumerCategory,
        ids: scope.providerCategoryIds,
        limit: scope.maxRowsPerScope
      })),
      [
        {
          country: "italy",
          category: "landmark",
          ids: ["landmark-id", "museum-id"],
          limit: 25
        },
        {
          country: "italy",
          category: "restaurant",
          ids: ["restaurant-id"],
          limit: 25
        }
      ]
    );
  });

  it("fails closed when a requested POI type has labels only and no provider IDs", () => {
    const plan = buildFsqCategoryCoveragePlan({
      countries: ["italy"],
      categories: ["poi", "landmark"],
      maxRowsPerScope: 10,
      sourceTaxonomy: taxonomy
    });
    assert.equal(plan.ok, false);
    if (plan.ok) return;
    assert.deepEqual(plan.blocks, ["source_category_query_ids_required:poi"]);
    assert.deepEqual(providerCategoryIdsForConsumerCategory(taxonomy, "poi"), []);
  });

  it("does not treat the fallback category as query coverage evidence", () => {
    assert.deepEqual(providerCategoryIdsForConsumerCategory(taxonomy, "poi"), []);
  });

  it("assesses missing requested scopes without inventing artifact zeros", () => {
    const assessment = assessFsqRequestedCoverage({
      countries: ["italy", "france"],
      categories: ["landmark", "restaurant"],
      byCountryAndPoiType: {
        italy: { landmark: 2 }
      }
    });
    assert.equal(assessment.requestedScopeCount, 4);
    assert.equal(assessment.coveredScopeCount, 1);
    assert.deepEqual(assessment.missingScopes, [
      { country: "france", category: "landmark" },
      { country: "france", category: "restaurant" },
      { country: "italy", category: "restaurant" }
    ]);
    assert.deepEqual(assessment.byCountryAndPoiType, { italy: { landmark: 2 } });

    const lines = formatFsqRequestedCoverageAssessment(assessment);
    assert.ok(lines.some((line) => line.includes("missing country / POI-type scopes:")));
    assert.ok(lines.some((line) => line.includes("italy/restaurant")));
    assert.doesNotMatch(lines.join("\n"), /token|secret|iceberg/i);
  });
});
