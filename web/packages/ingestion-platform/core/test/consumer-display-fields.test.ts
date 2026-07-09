import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import {
  resolveConsumerDisplayFields,
  resolveDefaultBatchQueueDisplayFields,
  VAMO_PLACE_INTELLIGENCE_QUEUE_DISPLAY_FIELDS
} from "../src/consumer-display-fields.js";
import { parseConsumerContractManifest } from "../../spec/src/consumer-contract.js";

const VAMO_IMPORTED_MANIFEST_URL = new URL(
  "../../../fixtures/imported/vamo-place-intelligence/manifest.yaml",
  import.meta.url
);

describe("consumer display fields", () => {
  it("uses the imported consumer manifest as the default queue display source", () => {
    const manifest = parseConsumerContractManifest(
      readFileSync(VAMO_IMPORTED_MANIFEST_URL, "utf8")
    );

    assert.equal(manifest.ok, true);
    if (!manifest.ok) {
      return;
    }

    assert.deepEqual(
      resolveDefaultBatchQueueDisplayFields({
        projectKey: "vamo",
        targetKey: "vamo-place-intelligence"
      }),
      manifest.value.display?.queue?.fields
    );
  });

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

  it("shows unsupported Vamo categories without a consumer mapping", () => {
    const fields = resolveConsumerDisplayFields(VAMO_PLACE_INTELLIGENCE_QUEUE_DISPLAY_FIELDS, {
      scope: {
        category: "museum",
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
        value: "Museum",
        detail: "No consumer mapping"
      }
    ]);
  });

  it("falls back to raw values for an unexpected display presenter", () => {
    const fields = resolveConsumerDisplayFields(
      [
        {
          key: "category",
          label: "Category",
          source: "scope.category",
          presenter: "unknown_presenter" as never
        }
      ],
      {
        scope: {
          category: "museum",
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
      }
    );

    assert.deepEqual(fields, [
      {
        key: "category",
        label: "Category",
        value: "museum"
      }
    ]);
  });
});
