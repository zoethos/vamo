import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  indexCoords,
  loadRoutingConfig,
  orsProfileForMode,
  pairCacheKey,
  parseOrsDistances,
  RoutingError,
} from "./routing.ts";

Deno.test("orsProfileForMode maps road modes; null for train/flight", () => {
  assertEquals(orsProfileForMode("car"), "driving-car");
  assertEquals(orsProfileForMode("motorbike"), "driving-car");
  assertEquals(orsProfileForMode("bus"), "driving-car");
  assertEquals(orsProfileForMode("bike"), "cycling-regular");
  assertEquals(orsProfileForMode("train"), null);
  assertEquals(orsProfileForMode("flight"), null);
});

Deno.test("pairCacheKey is stable and profile-scoped", () => {
  const from = { lat: 41.9, lng: 12.5 };
  const to = { lat: 40.85, lng: 14.25 };
  assertEquals(
    pairCacheKey(from, to, "driving-car"),
    pairCacheKey(from, to, "driving-car"),
  );
  assert(pairCacheKey(from, to, "driving-car").startsWith("driving-car|"));
  assert(
    pairCacheKey(from, to, "driving-car") !==
      pairCacheKey(from, to, "cycling-regular"),
  );
});

Deno.test("parseOrsDistances reads a matrix and nulls bad cells", () => {
  assertEquals(
    parseOrsDistances({ distances: [[0, 1234.5], [1234.5, 0]] }),
    [[0, 1234.5], [1234.5, 0]],
  );
  assertEquals(parseOrsDistances({}), null);
  assertEquals(parseOrsDistances("x"), null);
  assertEquals(parseOrsDistances({ distances: [[null, "bad"]] }), [[
    null,
    null,
  ]]);
});

Deno.test("indexCoords dedupes and addresses by ~11m key", () => {
  const { unique, indexOf } = indexCoords([
    { lat: 1, lng: 2 },
    { lat: 1, lng: 2 },
    { lat: 3, lng: 4 },
  ]);
  assertEquals(unique.length, 2);
  assertEquals(indexOf({ lat: 1, lng: 2 }), 0);
  assertEquals(indexOf({ lat: 3, lng: 4 }), 1);
});

Deno.test("loadRoutingConfig fails closed for non-ORS providers", () => {
  let threw = false;
  try {
    loadRoutingConfig({ provider: "mapbox", config: {} });
  } catch (e) {
    threw = e instanceof RoutingError;
  }
  assert(threw);

  const cfg = loadRoutingConfig({
    provider: "openrouteservice",
    config: { base_url: "https://example.test/", timeout_ms: 5000 },
  });
  assertEquals(cfg.adapter, "ors-matrix");
  assertEquals(cfg.baseUrl, "https://example.test/");
  assertEquals(cfg.timeoutMs, 5000);
});
