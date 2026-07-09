import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  describeVamoStagingTargetCategoryCompatibility,
  isVamoStagingTargetCategoryCompatible,
  mapVamoSourceCategoryToFeatureType
} from "../src/batch-staging-canary-wave-target-compat.js";

describe("Vamo staging target category compatibility", () => {
  it("maps source categories to supported Vamo target feature types", () => {
    assert.equal(mapVamoSourceCategoryToFeatureType("poi"), "poi");
    assert.equal(mapVamoSourceCategoryToFeatureType("landmark"), "landmark");
    assert.equal(mapVamoSourceCategoryToFeatureType("restaurant"), "poi");
    assert.equal(mapVamoSourceCategoryToFeatureType("transport"), "poi");
    assert.equal(mapVamoSourceCategoryToFeatureType("hotel"), "poi");
  });

  it("marks native poi and landmark categories as compatible", () => {
    for (const category of ["poi", "landmark"]) {
      assert.equal(isVamoStagingTargetCategoryCompatible(category), true);
      assert.equal(describeVamoStagingTargetCategoryCompatibility(category).status, "compatible");
    }
  });

  it("marks restaurant and transport as mapped POI subtypes", () => {
    for (const category of ["restaurant", "transport"]) {
      assert.equal(isVamoStagingTargetCategoryCompatible(category), true);
      const described = describeVamoStagingTargetCategoryCompatibility(category);
      assert.equal(described.status, "mapped");
      assert.equal(described.targetFeatureType, "poi");
      assert.match(described.detail, /POI subtype/);
    }
  });

  it("blocks unknown categories", () => {
    assert.equal(isVamoStagingTargetCategoryCompatible("venue"), false);
    assert.equal(describeVamoStagingTargetCategoryCompatibility("venue").status, "blocked");
  });
});
