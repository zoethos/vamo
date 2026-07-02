import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  equivalentTargetKeys,
  isLegacyTargetKey,
  lookupByTargetIdentity,
  VAMO_PLACE_INTELLIGENCE_TARGET_KEY
} from "../src/target-identity.js";

describe("target identity aliases", () => {
  it("expands canonical keys to include legacy aliases", () => {
    assert.deepEqual(equivalentTargetKeys(VAMO_PLACE_INTELLIGENCE_TARGET_KEY), [
      VAMO_PLACE_INTELLIGENCE_TARGET_KEY,
      "vamo-place-intelligence-staging"
    ]);
  });

  it("expands legacy alias keys back to the canonical key", () => {
    assert.deepEqual(equivalentTargetKeys("vamo-place-intelligence-staging"), [
      VAMO_PLACE_INTELLIGENCE_TARGET_KEY,
      "vamo-place-intelligence-staging"
    ]);
  });

  it("returns unknown keys unchanged", () => {
    assert.deepEqual(equivalentTargetKeys("other-target"), ["other-target"]);
  });

  it("classifies legacy alias keys", () => {
    assert.equal(isLegacyTargetKey("vamo-place-intelligence-staging"), true);
    assert.equal(isLegacyTargetKey(VAMO_PLACE_INTELLIGENCE_TARGET_KEY), false);
  });

  it("looks up shipment state by canonical or legacy ledger keys", () => {
    const map = new Map([
      [
        "vamo-place-intelligence-staging",
        { packageId: "production-inbox:vamo-place-intelligence-staging:approval:13" }
      ]
    ]);
    const hit = lookupByTargetIdentity(map, VAMO_PLACE_INTELLIGENCE_TARGET_KEY);
    assert.equal(hit?.packageId, "production-inbox:vamo-place-intelligence-staging:approval:13");
  });
});
