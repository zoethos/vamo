import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  classifyFsqPlaceConsumerCategory,
  extractFsqSourceTaxonomyFromPlan,
  parseFsqSourceTaxonomy
} from "../src/fsq-source-taxonomy.js";

const mapping = {
  provider: "fsq_os_places" as const,
  fallbackConsumerCategory: "poi",
  mappings: [
    {
      providerCategoryIds: ["museum-id"],
      providerCategoryLabels: ["museum"],
      consumerCategory: "landmark",
      precedence: 100
    },
    {
      providerCategoryIds: ["restaurant-id"],
      providerCategoryLabels: ["restaurant"],
      consumerCategory: "restaurant",
      precedence: 90
    },
    {
      providerCategoryIds: ["also-museum-id"],
      providerCategoryLabels: ["gallery"],
      consumerCategory: "landmark",
      precedence: 100
    }
  ]
};

describe("fsq source taxonomy", () => {
  it("parses declarative mappings with fallback", () => {
    const parsed = parseFsqSourceTaxonomy(mapping);
    assert.equal(parsed.ok, true);
    if (parsed.ok) {
      assert.equal(parsed.mapping.fallbackConsumerCategory, "poi");
      assert.equal(parsed.mapping.mappings.length, 3);
    }
  });

  it("assigns the highest-precedence consumer category deterministically", () => {
    const result = classifyFsqPlaceConsumerCategory({
      mapping,
      providerCategoryIds: ["restaurant-id", "museum-id"],
      providerCategoryLabels: ["Restaurant", "Museum"],
      allowedConsumerCategories: ["poi", "landmark", "restaurant"]
    });
    assert.deepEqual(result, {
      ok: true,
      consumerCategory: "landmark",
      matchedBy: "mapping"
    });
  });

  it("uses the single fallback category when nothing matches", () => {
    const result = classifyFsqPlaceConsumerCategory({
      mapping,
      providerCategoryIds: ["unknown"],
      providerCategoryLabels: ["Unknown Spot"],
      allowedConsumerCategories: ["poi", "landmark", "restaurant"]
    });
    assert.deepEqual(result, {
      ok: true,
      consumerCategory: "poi",
      matchedBy: "fallback"
    });
  });

  it("rejects ambiguous mappings at the same precedence", () => {
    const ambiguous = {
      ...mapping,
      mappings: [
        {
          providerCategoryIds: ["shared"],
          providerCategoryLabels: [],
          consumerCategory: "landmark",
          precedence: 50
        },
        {
          providerCategoryIds: ["shared"],
          providerCategoryLabels: [],
          consumerCategory: "restaurant",
          precedence: 50
        }
      ]
    };
    const result = classifyFsqPlaceConsumerCategory({
      mapping: ambiguous,
      providerCategoryIds: ["shared"],
      allowedConsumerCategories: ["landmark", "restaurant"]
    });
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.equal(result.block, "source_category_mapping_ambiguous:landmark,restaurant");
    }
  });

  it("fails closed when the active plan lacks sourceTaxonomy", () => {
    assert.deepEqual(extractFsqSourceTaxonomyFromPlan({ id: "vamo-eu-full-data-v1" }), {
      ok: false,
      blocks: ["source_mapping_requires_plan_refresh"]
    });
  });
});
