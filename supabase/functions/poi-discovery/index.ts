// D-P1.a — POI discovery gateway.
// Input:
//   nearby: { trip_id, lat, lng, query?, category?, radius? }
//   search: { trip_id, mode: "search", query, regionBias?, category?, session_id? }
// Auth: caller JWT required; trip row is selected through RLS so only members
// can resolve POIs for a trip. Provider keys stay server-side.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  completeServiceUsageReservation,
  recordPremiumGateNotification,
  releaseServiceUsageReservation,
  reserveServiceUsage,
} from "../_shared/premium.ts";
import { normalizeFoursquarePlaces, queryForCategory } from "./poi.ts";
import {
  cacheKeyForPoiInput,
  normalizeQuery,
  type PoiInput,
  readPoiInputFromBody,
} from "./request.ts";

const FOURSQUARE_SEARCH = "https://places-api.foursquare.com/places/search";
const SERVICE = "poi";
const DEFAULT_LIMIT = 12;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: "misconfigured" }, 503);
  }

  const input = await readInput(req);
  if (!input) return json({ error: "invalid_input" }, 400);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData } = await userClient.auth.getUser();
  const user = authData?.user;
  if (!user) return json({ error: "unauthorized" }, 401);

  const { data: trip, error: tripError } = await userClient
    .from("trips")
    .select("id,destination")
    .eq("id", input.tripId)
    .maybeSingle();
  if (tripError || !trip) return json({ error: "trip_not_found" }, 404);

  const serviceClient = createClient(supabaseUrl, serviceKey);
  const regionBias = input.mode === "search"
    ? normalizeQuery(input.regionBias) ?? normalizeQuery(trip.destination) ??
      null
    : null;
  if (input.mode === "search" && !regionBias) {
    return json({ available: false, reason: "missing_region_bias" });
  }
  const { cacheKey, geohash, category } = cacheKeyForPoiInput(
    SERVICE,
    "foursquare",
    input,
    regionBias,
  );

  const cached = await readCachedPois(serviceClient, cacheKey);
  if (cached) {
    return json({ available: true, pois: cached, cached: true });
  }

  const reservation = await reserveServiceUsage(serviceClient, {
    idempotencyKey: input.mode === "search" && input.sessionId
      ? `poi:search:${user.id}:${input.sessionId}`
      : crypto.randomUUID(),
    service: SERVICE,
    userId: user.id,
  });

  if (!reservation.reserved || reservation.gated) {
    const reason = reservation.reason ?? "quota_exceeded";
    await recordPremiumGateNotification(serviceClient, {
      userId: user.id,
      service: SERVICE,
      reason,
    });
    return json({ gated: true, upsell: SERVICE, reason });
  }

  if (reservation.provider !== "foursquare") {
    await releaseServiceUsageReservation(
      serviceClient,
      reservation.reservationId,
      "released",
    );
    return json({
      gated: true,
      upsell: SERVICE,
      reason: "provider_unavailable",
    });
  }

  const apiKey = Deno.env.get("FOURSQUARE_API_KEY")?.trim();
  if (!apiKey) {
    await releaseServiceUsageReservation(
      serviceClient,
      reservation.reservationId,
      "failed",
    );
    return json({ available: false, reason: "provider_unconfigured" });
  }

  try {
    const raw = await fetchFoursquare(apiKey, input, regionBias);
    const pois = normalizeFoursquarePlaces(raw);
    await completeServiceUsageReservation(
      serviceClient,
      reservation.reservationId,
    );
    if (reservation.canCacheContent) {
      await writeCachedPois(
        serviceClient,
        cacheKey,
        geohash,
        category,
        pois,
        reservation.cacheTtlSeconds ?? 604800,
      );
    }
    return json({ available: true, pois, cached: false });
  } catch (error) {
    console.error("poi-discovery provider failure", error);
    await releaseServiceUsageReservation(
      serviceClient,
      reservation.reservationId,
      "failed",
    );
    return json({ available: false, reason: "provider_unavailable" });
  }
});

async function readInput(req: Request): Promise<PoiInput | null> {
  try {
    return readPoiInputFromBody(await req.json());
  } catch {
    return null;
  }
}

async function readCachedPois(
  supabase: SupabaseClient,
  cacheKey: string,
): Promise<unknown[] | null> {
  const { data } = await supabase
    .from("poi_cache")
    .select("results, expires_at")
    .eq("cache_key", cacheKey)
    .maybeSingle();
  if (!data) return null;
  if (Date.parse(data.expires_at as string) <= Date.now()) return null;
  return Array.isArray(data.results) ? data.results : null;
}

async function writeCachedPois(
  supabase: SupabaseClient,
  cacheKey: string,
  geohash: string,
  category: string,
  pois: unknown[],
  ttlSeconds: number,
): Promise<void> {
  const expires = new Date(Date.now() + ttlSeconds * 1000).toISOString();
  await supabase.from("poi_cache").upsert(
    {
      cache_key: cacheKey,
      provider: "foursquare",
      geohash,
      category,
      results: pois,
      fetched_at: new Date().toISOString(),
      expires_at: expires,
    },
    { onConflict: "cache_key" },
  );
}

async function fetchFoursquare(
  apiKey: string,
  input: PoiInput,
  regionBias: string | null,
): Promise<unknown> {
  const url = new URL(FOURSQUARE_SEARCH);
  if (input.mode === "search") {
    url.searchParams.set("near", regionBias ?? "");
  } else {
    url.searchParams.set("ll", `${input.lat},${input.lng}`);
    url.searchParams.set("radius", `${input.radius}`);
  }
  url.searchParams.set("limit", `${DEFAULT_LIMIT}`);
  url.searchParams.set(
    "fields",
    "fsq_place_id,name,categories,fsq_category_labels,latitude,longitude,location,distance",
  );
  const query = queryForCategory(input.category);
  const searchQuery = input.query?.trim() || query;
  if (searchQuery) url.searchParams.set("query", searchQuery);

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    throw new Error(`Foursquare search failed: ${response.status}`);
  }
  return await response.json();
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
