import { assertEquals } from "jsr:@std/assert@1.0.19";
import { normalizeFoursquarePlaces, queryForCategory } from "./poi.ts";

Deno.test("normalizeFoursquarePlaces maps basic fields and category buckets", () => {
  const pois = normalizeFoursquarePlaces({
    results: [
      {
        fsq_place_id: "fsq-1",
        name: "Cafe Roma",
        latitude: 41.9,
        longitude: 12.5,
        distance: 128.6,
        categories: [{ name: "Coffee Shop" }],
        location: { formatted_address: "Via Roma 1" },
      },
    ],
  });

  assertEquals(pois, [
    {
      id: "fsq-1",
      providerPlaceId: "fsq-1",
      name: "Cafe Roma",
      category: "food",
      lat: 41.9,
      lng: 12.5,
      address: "Via Roma 1",
      distanceM: 129,
      source: "foursquare",
    },
  ]);
});

Deno.test("normalizeFoursquarePlaces drops malformed rows and maps unknown category", () => {
  const pois = normalizeFoursquarePlaces({
    results: [
      { name: "Missing ID", latitude: 1, longitude: 2 },
      {
        fsq_place_id: "fsq-2",
        name: "Odd Place",
        latitude: "48.1",
        longitude: "11.5",
        fsq_category_labels: ["Something Specific"],
        location: { address: "Street", locality: "Munich", country: "DE" },
      },
    ],
  });

  assertEquals(pois.length, 1);
  assertEquals(pois[0].category, "other");
  assertEquals(pois[0].address, "Street");
});

Deno.test("queryForCategory only maps Vamo buckets", () => {
  assertEquals(queryForCategory("food"), "restaurant");
  assertEquals(queryForCategory("transport"), "station");
  assertEquals(queryForCategory("all"), null);
  assertEquals(queryForCategory(null), null);
});
