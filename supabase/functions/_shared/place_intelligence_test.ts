import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.19";
import {
  aliasCollisionKey,
  assertPlaceProviderPolicy,
  normalizeAliasScope,
  normalizePlaceAlias,
} from "./place_intelligence.ts";

Deno.test("normalizePlaceAlias trims lowercases and compacts spaces", () => {
  assertEquals(normalizePlaceAlias("  San   Francisco  "), "san francisco");
});

Deno.test("provider policy allows open seeds and blocks live API global seeding", () => {
  assertPlaceProviderPolicy("fsq_os_places", "seed_global");
  assertPlaceProviderPolicy("geonames", "store_content");
  assertPlaceProviderPolicy("google_places_api", "store_place_id");

  assertThrows(
    () => assertPlaceProviderPolicy("google_places_api", "seed_global"),
    Error,
    "place_provider_policy_denied:google_places_api:seed_global",
  );
  assertThrows(
    () => assertPlaceProviderPolicy("foursquare_places_api", "store_photo"),
    Error,
    "place_provider_policy_denied:foursquare_places_api:store_photo",
  );
});

Deno.test("alias collision key is scoped by country feature and canonical", () => {
  const city = aliasCollisionKey({
    aliasNorm: "springfield",
    canonicalId: "city-1",
    scope: normalizeAliasScope({
      countryCode: "US",
      featureType: "locality",
    }),
  });
  const poi = aliasCollisionKey({
    aliasNorm: "springfield",
    canonicalId: "bar-1",
    scope: normalizeAliasScope({
      countryCode: "US",
      featureType: "poi",
    }),
  });
  const canada = aliasCollisionKey({
    aliasNorm: "springfield",
    canonicalId: "city-2",
    scope: normalizeAliasScope({
      countryCode: "CA",
      featureType: "locality",
    }),
  });

  assertEquals(city === poi, false);
  assertEquals(city === canada, false);
});
