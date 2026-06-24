import { assertEquals } from "jsr:@std/assert@1.0.19";
import {
  addressFromFoursquareLocation,
  classifyFoursquareProviderError,
  FoursquareHttpError,
  photoUrlFromFoursquarePhotos,
  queryForFoursquareCategory,
} from "./foursquare_places.ts";

Deno.test("queryForFoursquareCategory maps Vamo buckets", () => {
  assertEquals(queryForFoursquareCategory("food"), "restaurant");
  assertEquals(queryForFoursquareCategory("transport"), "station");
  assertEquals(queryForFoursquareCategory("all"), null);
  assertEquals(queryForFoursquareCategory(null), null);
});

Deno.test("photoUrlFromFoursquarePhotos prefers direct URL then prefix suffix", () => {
  assertEquals(
    photoUrlFromFoursquarePhotos([{ url: "https://img.example/direct.jpg" }]),
    "https://img.example/direct.jpg",
  );
  assertEquals(
    photoUrlFromFoursquarePhotos(
      [{ prefix: "https://img.example/", suffix: ".jpg" }],
      "original",
    ),
    "https://img.example/original.jpg",
  );
});

Deno.test("addressFromFoursquareLocation uses formatted address first", () => {
  assertEquals(
    addressFromFoursquareLocation({
      formatted_address: "Via Roma 1",
      locality: "Rome",
      country: "IT",
    }),
    "Via Roma 1",
  );
});

Deno.test("classifyFoursquareProviderError maps provider failures", () => {
  assertEquals(
    classifyFoursquareProviderError(new FoursquareHttpError(401)),
    "provider_auth",
  );
  assertEquals(
    classifyFoursquareProviderError(new FoursquareHttpError(429)),
    "provider_throttled",
  );
  assertEquals(
    classifyFoursquareProviderError(new TypeError("fetch failed")),
    "provider_network",
  );
});
