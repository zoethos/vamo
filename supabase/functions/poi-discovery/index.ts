// D-P1.a — POI discovery gateway.
// Input: { trip_id, lat, lng, category?, radius? }
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

const FOURSQUARE_SEARCH = "https://places-api.foursquare.com/places/search";
const SERVICE = "poi";
const DEFAULT_RADIUS_M = 1200;
const MAX_RADIUS_M = 5000;
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
    .select("id")
    .eq("id", input.tripId)
    .maybeSingle();
  if (tripError || !trip) return json({ error: "trip_not_found" }, 404);

  const serviceClient = createClient(supabaseUrl, serviceKey);
  const geohash = encodeGeohash(input.lat, input.lng, 6);
  const category = normalizeCategory(input.category);
  const cacheKey = `${SERVICE}:foursquare:${geohash}:${category}`;

  const cached = await readCachedPois(serviceClient, cacheKey);
  if (cached) {
    return json({ available: true, pois: cached, cached: true });
  }

  const reservation = await reserveServiceUsage(serviceClient, {
    idempotencyKey: crypto.randomUUID(),
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
    const raw = await fetchFoursquare(apiKey, input);
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

interface PoiInput {
  tripId: string;
  lat: number;
  lng: number;
  category: string | null;
  radius: number;
}

async function readInput(req: Request): Promise<PoiInput | null> {
  try {
    const body = await req.json();
    const tripId = stringValue(body?.trip_id);
    const lat = numberValue(body?.lat);
    const lng = numberValue(body?.lng);
    if (!tripId || lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    const radius = clampRadius(numberValue(body?.radius));
    return {
      tripId,
      lat,
      lng,
      category: stringValue(body?.category) ?? null,
      radius,
    };
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
): Promise<unknown> {
  const url = new URL(FOURSQUARE_SEARCH);
  url.searchParams.set("ll", `${input.lat},${input.lng}`);
  url.searchParams.set("radius", `${input.radius}`);
  url.searchParams.set("limit", `${DEFAULT_LIMIT}`);
  url.searchParams.set(
    "fields",
    "fsq_place_id,name,categories,fsq_category_labels,latitude,longitude,location,distance",
  );
  const query = queryForCategory(input.category);
  if (query) url.searchParams.set("query", query);

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

function normalizeCategory(raw: string | null): string {
  const value = raw?.trim().toLowerCase() ?? "";
  return [
      "food",
      "lodging",
      "attraction",
      "museum",
      "nature",
      "nightlife",
      "shopping",
      "transport",
    ].includes(value)
    ? value
    : "all";
}

function clampRadius(raw: number | undefined): number {
  if (raw == null) return DEFAULT_RADIUS_M;
  return Math.max(100, Math.min(MAX_RADIUS_M, Math.round(raw)));
}

function stringValue(raw: unknown): string | undefined {
  if (typeof raw !== "string") return undefined;
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function numberValue(raw: unknown): number | undefined {
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (typeof raw !== "string") return undefined;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function encodeGeohash(lat: number, lng: number, precision: number): string {
  const base32 = "0123456789bcdefghjkmnpqrstuvwxyz";
  let idx = 0;
  let bit = 0;
  let evenBit = true;
  let geohash = "";
  let latMin = -90;
  let latMax = 90;
  let lngMin = -180;
  let lngMax = 180;

  while (geohash.length < precision) {
    if (evenBit) {
      const mid = (lngMin + lngMax) / 2;
      if (lng >= mid) {
        idx = idx * 2 + 1;
        lngMin = mid;
      } else {
        idx = idx * 2;
        lngMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        idx = idx * 2 + 1;
        latMin = mid;
      } else {
        idx = idx * 2;
        latMax = mid;
      }
    }
    evenBit = !evenBit;

    if (++bit === 5) {
      geohash += base32.charAt(idx);
      bit = 0;
      idx = 0;
    }
  }
  return geohash;
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
