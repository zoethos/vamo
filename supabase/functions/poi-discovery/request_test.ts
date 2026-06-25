import {
  cacheKeyForPoiInput,
  readPoiInputFromBody,
  reservationKeyForSearchSession,
} from "./request.ts";
import { assertEquals } from "jsr:@std/assert@1.0.19";

Deno.test("readPoiInputFromBody accepts search without caller coordinates", () => {
  const input = readPoiInputFromBody({
    trip_id: "trip-1",
    mode: "search",
    query: "  Marienplatz  ",
    session_id: "session-1",
  });

  assertEquals(input?.mode, "search");
  assertEquals(input?.tripId, "trip-1");
  assertEquals(input?.query, "Marienplatz");
  assertEquals(input?.lat, 0);
  assertEquals(input?.lng, 0);
  assertEquals(input?.sessionId, "session-1");
});

Deno.test("readPoiInputFromBody rejects short search queries", () => {
  assertEquals(
    readPoiInputFromBody({
      trip_id: "trip-1",
      mode: "search",
      query: "jp",
    }),
    null,
  );
});

Deno.test("cacheKeyForPoiInput separates search sessions from nearby lookups", () => {
  const search = readPoiInputFromBody({
    trip_id: "trip-1",
    mode: "search",
    query: "Marienplatz",
    category: "attraction",
  });
  const nearby = readPoiInputFromBody({
    trip_id: "trip-1",
    lat: 48.137154,
    lng: 11.576124,
  });

  const searchKey = cacheKeyForPoiInput(
    "poi",
    "foursquare",
    search!,
    "Munich, Germany",
  );
  const nearbyKey = cacheKeyForPoiInput(
    "poi",
    "foursquare",
    nearby!,
    null,
  );

  assertEquals(
    searchKey.cacheKey,
    "poi:foursquare:search:near:munich-germany:attraction:marienplatz",
  );
  assertEquals(nearbyKey.cacheKey, "poi:foursquare:nearby:u281z7:all:any");
});

Deno.test("reservationKeyForSearchSession meters one search session once", () => {
  const userId = "9ada6512-b35e-4c54-ba86-493cf9fcbe87";
  const sessionId = "1782163965486578-29125152";

  const firstKey = reservationKeyForSearchSession("poi", userId, sessionId);
  const secondKey = reservationKeyForSearchSession("poi", userId, sessionId);
  const otherKey = reservationKeyForSearchSession(
    "poi",
    userId,
    "1782163965486578-29125153",
  );

  assertEquals(
    firstKey,
    "poi:search:9ada6512-b35e-4c54-ba86-493cf9fcbe87:1782163965486578-29125152",
  );
  assertEquals(secondKey, firstKey);
  assertEquals(otherKey === firstKey, false);
  assertEquals(reservationKeyForSearchSession("poi", userId, null), null);
});
