import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type {
  FsqPortalIcebergDuckDbRunner,
  FsqPortalPlaceRecord
} from "../src/fsq-os-places-portal-iceberg-acquire.js";
import {
  acquireFsqOsPlacesPortalIceberg,
  buildFsqPortalIcebergSelectSql,
  buildFsqPortalIcebergSetupSql,
  escapeSqlLiteral,
  FSQ_ACQUISITION_ALLOWED_CATEGORIES,
  FSQ_ACQUISITION_ALLOWED_COUNTRIES,
  validateFsqAcquisitionBounds
} from "../src/fsq-os-places-portal-iceberg-acquire.js";
import type { FsqSourceTaxonomyMapping } from "../../../core/src/fsq-source-taxonomy.js";

const sampleTaxonomy: FsqSourceTaxonomyMapping = {
  provider: "fsq_os_places",
  fallbackConsumerCategory: "poi",
  mappings: [
    {
      providerCategoryIds: ["4bf58dd8d48988d181941735"],
      providerCategoryLabels: ["museum"],
      consumerCategory: "landmark",
      precedence: 100
    },
    {
      providerCategoryIds: ["4d4b7105d754a06374d81259"],
      providerCategoryLabels: ["restaurant"],
      consumerCategory: "restaurant",
      precedence: 90
    }
  ]
};

const fixtureRecords: FsqPortalPlaceRecord[] = [
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

describe("acquireFsqOsPlacesPortalIceberg", () => {
  it("preview mode is write-free and never requires a portal token", async () => {
    const result = await acquireFsqOsPlacesPortalIceberg({
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

  it("execute mode rejects a missing portal access token", async () => {
    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["poi"],
      preview: false,
      sourceTaxonomy: sampleTaxonomy
    });
    assert.deepEqual(result, { ok: false, blocks: ["portal_access_token_missing"] });
  });

  it("execute mode rejects missing source taxonomy without fixtures", async () => {
    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["poi"],
      preview: false,
      portalAccessToken: "portal-token-secret"
    });
    assert.deepEqual(result, { ok: false, blocks: ["source_mapping_requires_plan_refresh"] });
  });

  it("normalizes fixture records deterministically without live provider calls", async () => {
    const first = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy", "france"],
      categories: ["poi", "landmark"],
      preview: false,
      portalAccessToken: "fixture-portal-token-not-used",
      fixtureRecords
    });
    const second = await acquireFsqOsPlacesPortalIceberg({
      countries: ["france", "italy"],
      categories: ["landmark", "poi"],
      preview: false,
      portalAccessToken: "fixture-portal-token-not-used",
      fixtureRecords
    });

    assert.equal(first.ok, true);
    assert.equal(second.ok, true);
    if (first.ok && !first.preview && second.ok && !second.preview) {
      assert.equal(first.normalizedJsonl, second.normalizedJsonl);
      assert.equal(first.providerRecordCount, 2);
      assert.match(first.normalizedJsonl, /fsq_rome_colosseum/);
      assert.match(first.normalizedJsonl, /fsq_paris_louvre/);
      assert.doesNotMatch(first.normalizedJsonl, /fixture-portal-token-not-used/);
    }
  });

  it("uses injectable DuckDB runner only when fixtures are not supplied", async () => {
    let queryCount = 0;
    const runner: FsqPortalIcebergDuckDbRunner = {
      async queryCountryPlaces(input) {
        queryCount += 1;
        assert.equal(input.countryIso, "IT");
        assert.equal(input.portalAccessToken, "portal-token-secret-value");
        return {
          ok: true,
          rows: [
            {
              fsqPlaceId: "rome_pantheon",
              name: "Pantheon",
              latitude: 41.8986,
              longitude: 12.4768,
              countryIso: "IT",
              locality: "Rome",
              providerCategoryIds: ["4bf58dd8d48988d181941735"],
              providerCategoryLabels: ["Museum"]
            }
          ]
        };
      }
    };

    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["landmark"],
      preview: false,
      portalAccessToken: "portal-token-secret-value",
      sourceTaxonomy: sampleTaxonomy,
      duckDbRunner: runner
    });

    assert.equal(queryCount, 1);
    assert.equal(result.ok, true);
    if (result.ok && !result.preview) {
      assert.match(result.normalizedJsonl, /fsq_rome_pantheon/);
      assert.match(result.normalizedJsonl, /"category":"landmark"/);
      assert.doesNotMatch(result.normalizedJsonl, /portal-token-secret-value/);
      assert.doesNotMatch(JSON.stringify(result), /portal-token-secret-value/);
    }
  });

  it("skips valid rows outside a bounded category request instead of rejecting the run", async () => {
    const runner: FsqPortalIcebergDuckDbRunner = {
      async queryCountryPlaces() {
        return {
          ok: true,
          rows: [
            {
              fsqPlaceId: "rome_general_poi",
              name: "General place",
              latitude: 41.9,
              longitude: 12.5,
              countryIso: "IT",
              locality: "Rome",
              providerCategoryIds: [],
              providerCategoryLabels: ["Business and Professional Services > Spa"]
            },
            {
              fsqPlaceId: "rome_restaurant",
              name: "Restaurant",
              latitude: 41.91,
              longitude: 12.51,
              countryIso: "IT",
              locality: "Rome",
              providerCategoryIds: ["4d4b7105d754a06374d81259"],
              providerCategoryLabels: ["Dining and Drinking > Restaurant"]
            }
          ]
        };
      }
    };

    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["restaurant"],
      maxRowsPerScope: 2,
      preview: false,
      portalAccessToken: "portal-token-secret-value",
      sourceTaxonomy: sampleTaxonomy,
      duckDbRunner: runner
    });

    assert.equal(result.ok, true);
    if (result.ok && !result.preview) {
      assert.equal(result.providerRecordCount, 1);
      assert.match(result.normalizedJsonl, /rome_restaurant/);
      assert.doesNotMatch(result.normalizedJsonl, /rome_general_poi/);
    }
  });

  it("orders bounded Iceberg reads before applying the limit", () => {
    const query = buildFsqPortalIcebergSelectSql({
      countryIso: "IT",
      limit: 25
    });
    assert.match(query.sql, /ORDER BY fsq_place_id ASC\s+LIMIT \$limit/);
  });

  it("interrupts on query timeout and returns a safe operator block", async () => {
    let interrupted = false;
    const runner: FsqPortalIcebergDuckDbRunner = {
      async queryCountryPlaces() {
        interrupted = true;
        return { ok: false, block: "portal_query_timeout" };
      }
    };

    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["poi"],
      preview: false,
      portalAccessToken: "portal-token-timeout",
      sourceTaxonomy: sampleTaxonomy,
      duckDbRunner: runner,
      queryTimeoutMs: 1
    });

    assert.equal(interrupted, true);
    assert.deepEqual(result, { ok: false, blocks: ["portal_query_timeout"] });
    assert.doesNotMatch(JSON.stringify(result), /portal-token-timeout/);
  });

  it("rejects expired or unauthorized portal tokens without leaking the token", async () => {
    const runner: FsqPortalIcebergDuckDbRunner = {
      async queryCountryPlaces() {
        return { ok: false, block: "portal_access_token_rejected" };
      }
    };

    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["poi"],
      preview: false,
      portalAccessToken: "expired-portal-token-xyz",
      sourceTaxonomy: sampleTaxonomy,
      duckDbRunner: runner
    });

    assert.deepEqual(result, { ok: false, blocks: ["portal_access_token_rejected"] });
    assert.doesNotMatch(JSON.stringify(result), /expired-portal-token-xyz/);
  });

  it("fails before querying when configured Portal token expiry has elapsed", async () => {
    let queried = false;
    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["poi"],
      preview: false,
      portalAccessToken: "expired-portal-token-xyz",
      portalAccessTokenExpiresAt: "2026-07-01T00:00:00.000Z",
      now: "2026-07-01T00:00:00.000Z",
      sourceTaxonomy: sampleTaxonomy,
      duckDbRunner: {
        async queryCountryPlaces() {
          queried = true;
          return { ok: false, block: "portal_access_token_rejected" };
        }
      }
    });

    assert.deepEqual(result, { ok: false, blocks: ["portal_access_token_expired"] });
    assert.equal(queried, false);
  });

  it("escapes portal tokens only for CREATE SECRET SQL", () => {
    const setup = buildFsqPortalIcebergSetupSql({
      portalAccessToken: "tok'en-with-quote"
    });
    assert.match(setup.createSecretSql, /TOKEN 'tok''en-with-quote'/);
    assert.equal(escapeSqlLiteral("a'b"), "a''b");
  });
});
