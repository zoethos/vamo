import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type {
  FsqPortalIcebergDuckDbRunner,
  FsqPortalIcebergQueryRow,
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
    },
    {
      providerCategoryIds: ["4d4b7104d754a06370d81259"],
      providerCategoryLabels: ["arts and entertainment"],
      consumerCategory: "poi",
      precedence: 10
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

function row(partial: Partial<FsqPortalIcebergQueryRow> & Pick<FsqPortalIcebergQueryRow, "fsqPlaceId" | "name">): FsqPortalIcebergQueryRow {
  return {
    latitude: 41.9,
    longitude: 12.5,
    countryIso: "IT",
    locality: "Rome",
    providerCategoryIds: [],
    providerCategoryLabels: [],
    ...partial
  };
}

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
      assert.ok(
        first.normalizedJsonl.indexOf("fsq_paris_louvre") <
          first.normalizedJsonl.indexOf("fsq_rome_colosseum"),
        "normalized output is ordered by FSQ place id"
      );
      assert.doesNotMatch(first.normalizedJsonl, /fixture-portal-token-not-used/);
    }
  });

  it("issues one bounded runner call per country and POI type", async () => {
    const calls: Array<{ countryIso: string; providerCategoryIds: readonly string[]; limit: number }> =
      [];
    const runner: FsqPortalIcebergDuckDbRunner = {
      async queryCountryCategoryPlaces(input) {
        calls.push({
          countryIso: input.countryIso,
          providerCategoryIds: input.providerCategoryIds,
          limit: input.limit
        });
        if (input.providerCategoryIds.includes("4bf58dd8d48988d181941735")) {
          return {
            ok: true,
            rows: [
              row({
                fsqPlaceId: "rome_pantheon",
                name: "Pantheon",
                providerCategoryIds: ["4bf58dd8d48988d181941735"],
                providerCategoryLabels: ["Museum"]
              })
            ]
          };
        }
        return {
          ok: true,
          rows: [
            row({
              fsqPlaceId: "rome_trattoria",
              name: "Trattoria",
              providerCategoryIds: ["4d4b7105d754a06374d81259"],
              providerCategoryLabels: ["Restaurant"]
            })
          ]
        };
      }
    };

    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["landmark", "restaurant"],
      maxRowsPerScope: 3,
      preview: false,
      portalAccessToken: "portal-token-secret-value",
      sourceTaxonomy: sampleTaxonomy,
      duckDbRunner: runner
    });

    assert.equal(calls.length, 2);
    assert.deepEqual(
      calls.map((call) => ({
        countryIso: call.countryIso,
        ids: [...call.providerCategoryIds],
        limit: call.limit
      })),
      [
        { countryIso: "IT", ids: ["4bf58dd8d48988d181941735"], limit: 3 },
        { countryIso: "IT", ids: ["4d4b7105d754a06374d81259"], limit: 3 }
      ]
    );
    assert.equal(result.ok, true);
    if (result.ok && !result.preview) {
      assert.equal(result.providerRecordCount, 2);
      assert.match(result.normalizedJsonl, /rome_pantheon/);
      assert.match(result.normalizedJsonl, /rome_trattoria/);
      assert.doesNotMatch(JSON.stringify(result), /portal-token-secret-value/);
    }
  });

  it("prevents one category from consuming another category's limit", async () => {
    const runner: FsqPortalIcebergDuckDbRunner = {
      async queryCountryCategoryPlaces(input) {
        if (input.providerCategoryIds.includes("4bf58dd8d48988d181941735")) {
          return {
            ok: true,
            rows: Array.from({ length: 5 }, (_, index) =>
              row({
                fsqPlaceId: `rome_landmark_${index}`,
                name: `Landmark ${index}`,
                providerCategoryIds: ["4bf58dd8d48988d181941735"],
                providerCategoryLabels: ["Museum"]
              })
            )
          };
        }
        return {
          ok: true,
          rows: [
            row({
              fsqPlaceId: "rome_restaurant_only",
              name: "Restaurant only",
              providerCategoryIds: ["4d4b7105d754a06374d81259"],
              providerCategoryLabels: ["Restaurant"]
            })
          ]
        };
      }
    };

    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["landmark", "restaurant"],
      maxRowsPerScope: 2,
      preview: false,
      portalAccessToken: "portal-token-budget",
      sourceTaxonomy: sampleTaxonomy,
      duckDbRunner: runner
    });

    assert.equal(result.ok, true);
    if (result.ok && !result.preview) {
      assert.equal(result.providerRecordCount, 3);
      assert.match(result.normalizedJsonl, /rome_restaurant_only/);
      assert.match(result.normalizedJsonl, /rome_landmark_0/);
      assert.match(result.normalizedJsonl, /rome_landmark_1/);
      assert.doesNotMatch(result.normalizedJsonl, /rome_landmark_2/);
    }
  });

  it("blocks labels-only taxonomy before calling the runner", async () => {
    let queried = false;
    const labelsOnly: FsqSourceTaxonomyMapping = {
      provider: "fsq_os_places",
      fallbackConsumerCategory: "poi",
      mappings: [
        {
          providerCategoryIds: [],
          providerCategoryLabels: ["museum"],
          consumerCategory: "landmark",
          precedence: 100
        }
      ]
    };
    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["landmark"],
      preview: false,
      portalAccessToken: "portal-token-labels-only",
      sourceTaxonomy: labelsOnly,
      duckDbRunner: {
        async queryCountryCategoryPlaces() {
          queried = true;
          return { ok: true, rows: [] };
        }
      }
    });
    assert.equal(queried, false);
    assert.deepEqual(result, {
      ok: false,
      blocks: ["source_category_query_ids_required:landmark"]
    });
  });

  it("discards rows that classify to a different POI type than the query scope", async () => {
    const runner: FsqPortalIcebergDuckDbRunner = {
      async queryCountryCategoryPlaces() {
        return {
          ok: true,
          rows: [
            row({
              fsqPlaceId: "rome_misclassified",
              name: "Actually a restaurant",
              // Provider ID match for landmark query, but taxonomy classifies to restaurant.
              providerCategoryIds: ["4d4b7105d754a06374d81259"],
              providerCategoryLabels: ["Restaurant"]
            }),
            row({
              fsqPlaceId: "rome_true_landmark",
              name: "True landmark",
              providerCategoryIds: ["4bf58dd8d48988d181941735"],
              providerCategoryLabels: ["Museum"]
            })
          ]
        };
      }
    };

    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["landmark"],
      preview: false,
      portalAccessToken: "portal-token-classify",
      sourceTaxonomy: sampleTaxonomy,
      duckDbRunner: runner
    });

    assert.equal(result.ok, true);
    if (result.ok && !result.preview) {
      assert.equal(result.providerRecordCount, 1);
      assert.match(result.normalizedJsonl, /rome_true_landmark/);
      assert.doesNotMatch(result.normalizedJsonl, /rome_misclassified/);
    }
  });

  it("deduplicates by FSQ place id deterministically across scopes", async () => {
    const runner: FsqPortalIcebergDuckDbRunner = {
      async queryCountryCategoryPlaces() {
        return {
          ok: true,
          rows: [
            row({
              fsqPlaceId: "shared_place",
              name: "Shared",
              providerCategoryIds: ["4bf58dd8d48988d181941735"],
              providerCategoryLabels: ["Museum"]
            })
          ]
        };
      }
    };

    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["landmark"],
      preview: false,
      portalAccessToken: "portal-token-dedupe",
      sourceTaxonomy: sampleTaxonomy,
      duckDbRunner: runner
    });

    assert.equal(result.ok, true);
    if (result.ok && !result.preview) {
      assert.equal(result.providerRecordCount, 1);
      assert.equal((result.normalizedJsonl.match(/shared_place/g) ?? []).length, 1);
    }
  });

  it("resolves direct and parent provider category IDs through the FSQ categories table", () => {
    const query = buildFsqPortalIcebergSelectSql({
      countryIso: "IT",
      providerCategoryIds: ["id-a", "id-b"],
      limit: 25
    });
    assert.match(query.sql, /WITH matching_categories AS/);
    assert.match(query.sql, /FROM places\.datasets\.categories/);
    assert.match(query.sql, /category_id = \$providerCategoryId0/);
    assert.match(query.sql, /level2_category_id = \$providerCategoryId1/);
    assert.match(query.sql, /CROSS JOIN UNNEST\(p\.fsq_category_ids\)/);
    assert.match(query.sql, /WHERE p\.country = \$countryIso/);
    assert.match(query.sql, /ORDER BY p\.fsq_place_id ASC\s+LIMIT \$limit/);
    assert.equal(query.params.providerCategoryId0, "id-a");
    assert.equal(query.params.providerCategoryId1, "id-b");
    assert.doesNotMatch(query.sql, /id-a|id-b/);
  });

  it("interrupts on query timeout and returns a safe operator block", async () => {
    let interrupted = false;
    const runner: FsqPortalIcebergDuckDbRunner = {
      async queryCountryCategoryPlaces() {
        interrupted = true;
        return { ok: false, block: "portal_query_timeout" };
      }
    };

    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["landmark"],
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
      async queryCountryCategoryPlaces() {
        return { ok: false, block: "portal_access_token_rejected" };
      }
    };

    const result = await acquireFsqOsPlacesPortalIceberg({
      countries: ["italy"],
      categories: ["landmark"],
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
      categories: ["landmark"],
      preview: false,
      portalAccessToken: "expired-portal-token-xyz",
      portalAccessTokenExpiresAt: "2026-07-01T00:00:00.000Z",
      now: "2026-07-01T00:00:00.000Z",
      sourceTaxonomy: sampleTaxonomy,
      duckDbRunner: {
        async queryCountryCategoryPlaces() {
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
