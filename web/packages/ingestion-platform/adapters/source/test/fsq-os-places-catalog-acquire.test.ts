import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

import type { FsqCatalogPlaceRecord } from "../src/fsq-os-places-catalog-acquire.js";
import {
  acquireFsqOsPlacesCatalog,
  FSQ_ACQUISITION_ALLOWED_CATEGORIES,
  FSQ_ACQUISITION_ALLOWED_COUNTRIES,
  validateFsqAcquisitionBounds
} from "../src/fsq-os-places-catalog-acquire.js";

const fixtureRecords: FsqCatalogPlaceRecord[] = [
  {
    fsqPlaceId: "rome_colosseum",
    name: "Colosseum",
    latitude: 41.8902,
    longitude: 12.4922,
    geography: "rome-italy",
    category: "landmark"
  },
  {
    fsqPlaceId: "paris_louvre",
    name: "Louvre Museum",
    latitude: 48.8606,
    longitude: 2.3376,
    geography: "paris-france",
    category: "poi"
  }
];

describe("validateFsqAcquisitionBounds", () => {
  it("accepts bounded country and category scopes", () => {
    const result = validateFsqAcquisitionBounds({
      countries: ["italy", "france"],
      categories: ["poi", "landmark"]
    });
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.plan.scopes.length, 4);
      assert.deepEqual(result.plan.countries, ["france", "italy"]);
    }
  });

  it("rejects out-of-bounds countries and categories", () => {
    const result = validateFsqAcquisitionBounds({
      countries: ["italy", "atlantis"],
      categories: ["poi", "spaceship"]
    });
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.ok(result.blocks.includes("country_out_of_bounds:atlantis"));
      assert.ok(result.blocks.includes("category_out_of_bounds:spaceship"));
    }
  });

  it("rejects empty scopes and invalid row limits", () => {
    assert.deepEqual(
      validateFsqAcquisitionBounds({ countries: [], categories: ["poi"] }),
      { ok: false, blocks: ["countries_required"] }
    );
    assert.deepEqual(
      validateFsqAcquisitionBounds({ countries: ["italy"], categories: [] }),
      { ok: false, blocks: ["categories_required"] }
    );
    assert.ok(
      !validateFsqAcquisitionBounds({
        countries: ["italy"],
        categories: ["poi"],
        maxRowsPerScope: 5000
      }).ok
    );
  });

  it("documents the allowed acquisition envelope", () => {
    assert.ok(FSQ_ACQUISITION_ALLOWED_COUNTRIES.includes("italy"));
    assert.ok(FSQ_ACQUISITION_ALLOWED_CATEGORIES.includes("poi"));
  });
});

describe("acquireFsqOsPlacesCatalog", () => {
  it("preview mode is write-free and never requires a service API key", async () => {
    const result = await acquireFsqOsPlacesCatalog({
      countries: ["italy"],
      categories: ["poi"],
      preview: true
    });
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.preview, true);
      assert.equal(result.normalizedJsonl, "");
      assert.equal(result.providerRecordCount, 0);
    }
  });

  it("execute mode rejects a missing service API key", async () => {
    const result = await acquireFsqOsPlacesCatalog({
      countries: ["italy"],
      categories: ["poi"],
      preview: false
    });
    assert.deepEqual(result, { ok: false, blocks: ["catalog_service_api_key_missing"] });
  });

  it("normalizes fixture records deterministically without live HTTP", async () => {
    const first = await acquireFsqOsPlacesCatalog({
      countries: ["italy", "france"],
      categories: ["poi", "landmark"],
      preview: false,
      serviceApiKey: "fixture-service-api-key-not-used",
      fixtureRecords
    });
    const second = await acquireFsqOsPlacesCatalog({
      countries: ["france", "italy"],
      categories: ["landmark", "poi"],
      preview: false,
      serviceApiKey: "fixture-service-api-key-not-used",
      fixtureRecords
    });

    assert.equal(first.ok, true);
    assert.equal(second.ok, true);
    if (first.ok && !first.preview && second.ok && !second.preview) {
      assert.equal(first.normalizedJsonl, second.normalizedJsonl);
      assert.equal(first.providerRecordCount, 2);
      assert.match(first.normalizedJsonl, /fsq_rome_colosseum/);
      assert.match(first.normalizedJsonl, /fsq_paris_louvre/);
      assert.doesNotMatch(first.normalizedJsonl, /fixture-token-not-used/);
    }
  });

  it("uses injectable fetch only when fixtures are not supplied", async () => {
    let fetchCount = 0;
    const result = await acquireFsqOsPlacesCatalog({
      countries: ["italy"],
      categories: ["poi"],
      preview: false,
      serviceApiKey: "test-service-api-key",
      fetchFn: async () => {
        fetchCount += 1;
        return {
          ok: true,
          status: 200,
          body: JSON.stringify({
            places: [
              {
                fsq_place_id: "rome_pantheon",
                name: "Pantheon",
                latitude: 41.8986,
                longitude: 12.4768,
                geography: "rome-italy",
                category: "poi"
              }
            ]
          })
        };
      }
    });

    assert.equal(fetchCount, 1);
    assert.equal(result.ok, true);
    if (result.ok && !result.preview) {
      assert.match(result.normalizedJsonl, /fsq_rome_pantheon/);
      assert.doesNotMatch(result.normalizedJsonl, /test-token/);
    }
  });
});
