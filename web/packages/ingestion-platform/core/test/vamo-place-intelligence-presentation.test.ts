import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { presentVamoPoiType } from "../src/vamo-place-intelligence-presentation.js";

describe("Vamo place intelligence presentation", () => {
  it("presents the generic poi category as General", () => {
    assert.deepEqual(presentVamoPoiType("poi"), {
      operatorLabel: "POI type",
      operatorValue: "General",
      technicalMapping: "feature_type=poi"
    });
  });

  it("presents restaurant as a POI subtype mapped to feature_type=poi", () => {
    assert.deepEqual(presentVamoPoiType("restaurant"), {
      operatorLabel: "POI type",
      operatorValue: "Restaurant",
      technicalMapping: "feature_type=poi"
    });
  });

  it("presents transport as a POI subtype mapped to feature_type=poi", () => {
    assert.deepEqual(presentVamoPoiType("transport"), {
      operatorLabel: "POI type",
      operatorValue: "Transport",
      technicalMapping: "feature_type=poi"
    });
  });

  it("presents landmark as its own POI type mapped to feature_type=landmark", () => {
    assert.deepEqual(presentVamoPoiType("landmark"), {
      operatorLabel: "POI type",
      operatorValue: "Landmark",
      technicalMapping: "feature_type=landmark"
    });
  });
});
