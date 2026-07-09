import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  resolveConsumerDisplayFields,
  VAMO_PLACE_INTELLIGENCE_QUEUE_DISPLAY_FIELDS
} from "../src/consumer-display-fields.js";

describe("consumer display fields", () => {
  for (const [category, expectedValue, expectedDetail] of [
    ["poi", "General", "feature_type=poi"],
    ["restaurant", "Restaurant", "feature_type=poi"],
    ["transport", "Transport", "feature_type=poi"],
    ["landmark", "Landmark", "feature_type=landmark"]
  ] as const) {
    it(`resolves Vamo ${category} as ${expectedValue}`, () => {
      const fields = resolveConsumerDisplayFields(VAMO_PLACE_INTELLIGENCE_QUEUE_DISPLAY_FIELDS, {
        scope: {
          category,
          geography: "barcelona-spain",
          country: "spain"
        },
        source: {
          key: "fsq-os-places-sample"
        },
        target: {
          key: "vamo-place-intelligence",
          environment: "staging"
        }
      });

      assert.deepEqual(fields, [
        {
          key: "poi_type",
          label: "POI type",
          value: expectedValue,
          detail: expectedDetail
        }
      ]);
    });
  }
});
