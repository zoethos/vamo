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

Deno.test("normalizeFoursquarePlaces maps optional place info fields", () => {
  const pois = normalizeFoursquarePlaces({
    results: [
      {
        fsq_place_id: "fsq-info",
        name: "Abbazia di Montecassino",
        latitude: 41.49,
        longitude: 13.81,
        categories: [{ name: "Historic Site" }],
        location: { formatted_address: "Via Montecassino" },
        description: "Historic abbey above Cassino.",
        tel: "+390000",
        website: "https://example.com",
        hours: { display: "Mon-Sun 09:00-17:00" },
        rating: 9.1,
        price: 2,
        photos: [{ prefix: "https://img.example/", suffix: ".jpg" }],
      },
    ],
  });

  assertEquals(pois[0], {
    id: "fsq-info",
    providerPlaceId: "fsq-info",
    name: "Abbazia di Montecassino",
    category: "attraction",
    lat: 41.49,
    lng: 13.81,
    address: "Via Montecassino",
    about: "Historic abbey above Cassino.",
    website: "https://example.com",
    phone: "+390000",
    hours: "Mon-Sun 09:00-17:00",
    rating: 9.1,
    priceLevel: 2,
    photoUrl: "https://img.example/300x300.jpg",
    source: "foursquare",
  });
});

Deno.test("queryForCategory only maps Vamo buckets", () => {
  assertEquals(queryForCategory("food"), "restaurant");
  assertEquals(queryForCategory("transport"), "station");
  assertEquals(queryForCategory("all"), null);
  assertEquals(queryForCategory(null), null);
});
