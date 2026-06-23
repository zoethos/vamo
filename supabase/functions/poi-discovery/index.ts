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
  reservationKeyForSearchSession,
} from "./request.ts";

const FOURSQUARE_SEARCH = "https://places-api.foursquare.com/places/search";
const FOURSQUARE_API_VERSION = "2025-06-17";
const SERVICE = "poi";
const DEFAULT_LIMIT = 12;

interface TripRow {
  id: string;
  name?: string | null;
  destination?: string | null;
}

interface PoiUsageEvent {
  operation: "search" | "nearby";
  status: "success" | "error" | "throttled" | "invalid_output";
  cached: boolean;
  latencyMs: number;
  errorKind?: string;
  metadata?: Record<string, unknown>;
}

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
  const startedAt = performance.now();

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
    .select("id,name,destination")
    .eq("id", input.tripId)
    .maybeSingle();
  if (tripError || !trip) return json({ error: "trip_not_found" }, 404);

  const serviceClient = createClient(supabaseUrl, serviceKey);
  const tripRow = trip as TripRow;
  const regionBias = input.mode === "search"
    ? normalizeQuery(input.regionBias) ?? normalizeQuery(trip.destination) ??
      normalizeQuery(tripRow.name ?? null) ??
      null
    : null;
  const usageMetadata = await usageMetadataForInput(input, tripRow, regionBias);
  if (input.mode === "search" && !regionBias) {
    await recordPoiUsage(serviceClient, {
      operation: "search",
      status: "error",
      cached: false,
      latencyMs: elapsedMs(startedAt),
      errorKind: "missing_region_bias",
      metadata: usageMetadata,
    });
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
    await recordPoiUsage(serviceClient, {
      operation: input.mode,
      status: "success",
      cached: true,
      latencyMs: elapsedMs(startedAt),
      metadata: { ...usageMetadata, result_count: cached.length },
    });
    return json({ available: true, pois: cached, cached: true });
  }

  let reservation;
  try {
    const searchSessionKey = input.mode === "search"
      ? reservationKeyForSearchSession(SERVICE, user.id, input.sessionId)
      : null;
    const idempotencyKey = searchSessionKey ?? crypto.randomUUID();
    reservation = await reserveServiceUsage(serviceClient, {
      idempotencyKey,
      service: SERVICE,
      userId: user.id,
    });
  } catch (error) {
    console.error("poi-discovery reservation failure", error);
    await recordPoiUsage(serviceClient, {
      operation: input.mode,
      status: "error",
      cached: false,
      latencyMs: elapsedMs(startedAt),
      errorKind: "reservation_failed",
      metadata: usageMetadata,
    });
    return json({ available: false, reason: "reservation_failed" }, 503);
  }

  if (reservation.gated) {
    const reason = reservation.reason ?? "quota_exceeded";
    await recordPremiumGateNotification(serviceClient, {
      userId: user.id,
      service: SERVICE,
      reason,
    });
    await recordPoiUsage(serviceClient, {
      operation: input.mode,
      status: "throttled",
      cached: false,
      latencyMs: elapsedMs(startedAt),
      errorKind: reason,
      metadata: usageMetadata,
    });
    return json({ gated: true, upsell: SERVICE, reason });
  }
  if (!reservation.reserved) {
    const reason = reservation.reason ??
      (reservation.status === "failed" || reservation.status === "released"
        ? "reservation_retry_required"
        : "provider_unavailable");
    console.error("poi-discovery reservation unavailable", {
      status: reservation.status ?? "unknown",
      reason,
    });
    await recordPoiUsage(serviceClient, {
      operation: input.mode,
      status: "error",
      cached: false,
      latencyMs: elapsedMs(startedAt),
      errorKind: reason,
      metadata: usageMetadata,
    });
    return json({ available: false, reason });
  }

  if (reservation.provider !== "foursquare") {
    await releaseServiceUsageReservation(
      serviceClient,
      reservation.reservationId,
      "released",
    );
    await recordPoiUsage(serviceClient, {
      operation: input.mode,
      status: "throttled",
      cached: false,
      latencyMs: elapsedMs(startedAt),
      errorKind: "provider_unavailable",
      metadata: usageMetadata,
    });
    return json({ available: false, reason: "provider_unavailable" });
  }

  const apiKey = Deno.env.get("FOURSQUARE_API_KEY")?.trim();
  if (!apiKey) {
    await releaseServiceUsageReservation(
      serviceClient,
      reservation.reservationId,
      "failed",
    );
    await recordPoiUsage(serviceClient, {
      operation: input.mode,
      status: "error",
      cached: false,
      latencyMs: elapsedMs(startedAt),
      errorKind: "provider_unconfigured",
      metadata: usageMetadata,
    });
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
    await recordPoiUsage(serviceClient, {
      operation: input.mode,
      status: "success",
      cached: false,
      latencyMs: elapsedMs(startedAt),
      metadata: { ...usageMetadata, result_count: pois.length },
    });
    return json({ available: true, pois, cached: false });
  } catch (error) {
    const errorKind = classifyPoiProviderError(error);
    console.error("poi-discovery provider failure", error);
    await releaseServiceUsageReservation(
      serviceClient,
      reservation.reservationId,
      "failed",
    );
    await recordPoiUsage(serviceClient, {
      operation: input.mode,
      status: "error",
      cached: false,
      latencyMs: elapsedMs(startedAt),
      errorKind,
      metadata: {
        ...usageMetadata,
        provider_status: error instanceof FoursquareHttpError
          ? error.status
          : null,
      },
    });
    return json({ available: false, reason: errorKind });
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
    [
      "fsq_place_id",
      "name",
      "categories",
      "latitude",
      "longitude",
      "location",
      "distance",
      "description",
      "tel",
      "website",
      "hours",
      "rating",
      "price",
      "photos",
    ].join(","),
  );
  const query = queryForCategory(input.category);
  const searchQuery = input.query?.trim() || query;
  if (searchQuery) url.searchParams.set("query", searchQuery);

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
      Accept: "application/json",
      "X-Places-Api-Version": FOURSQUARE_API_VERSION,
    },
  });
  if (!response.ok) {
    throw new FoursquareHttpError(response.status);
  }
  return await response.json();
}

class FoursquareHttpError extends Error {
  constructor(readonly status: number) {
    super(`Foursquare search failed: ${status}`);
    this.name = "FoursquareHttpError";
  }
}

function classifyPoiProviderError(error: unknown): string {
  if (error instanceof FoursquareHttpError) {
    if (error.status === 401 || error.status === 403) return "provider_auth";
    if (error.status === 429) return "provider_throttled";
    if (error.status >= 400 && error.status < 500) {
      return "provider_bad_request";
    }
    return "provider_error";
  }
  if (error instanceof TypeError) return "provider_network";
  return "provider_error";
}

async function usageMetadataForInput(
  input: PoiInput,
  trip: TripRow,
  regionBias: string | null,
): Promise<Record<string, unknown>> {
  return {
    mode: input.mode,
    category: input.category ?? "all",
    query_present: input.query != null,
    query_length: input.query?.length ?? 0,
    query_hash: await hashText(input.query),
    has_request_region_bias: input.regionBias != null,
    trip_has_destination: normalizeQuery(trip.destination ?? null) != null,
    trip_has_name: normalizeQuery(trip.name ?? null) != null,
    region_bias_source: regionBias == null
      ? null
      : normalizeQuery(input.regionBias) != null
      ? "request"
      : normalizeQuery(trip.destination ?? null) != null
      ? "trip_destination"
      : "trip_name",
    region_hash: await hashText(regionBias),
    radius: input.mode === "nearby" ? input.radius : null,
  };
}

async function hashText(value: string | null): Promise<string | null> {
  const normalized = normalizeQuery(value);
  if (normalized == null) return null;
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(normalized),
  );
  return Array.from(new Uint8Array(bytes))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function recordPoiUsage(
  supabase: SupabaseClient,
  event: PoiUsageEvent,
): Promise<void> {
  try {
    await supabase.from("provider_usage_events").insert({
      feature: SERVICE,
      provider: "foursquare",
      model: null,
      operation: event.operation,
      status: event.status,
      cached: event.cached,
      input_units: null,
      output_units: null,
      estimated_cost_usd: null,
      latency_ms: event.latencyMs,
      error_kind: event.errorKind ?? null,
      metadata: event.metadata ?? {},
    });
  } catch (error) {
    console.error("poi provider_usage_events insert failed", error);
  }
}

function elapsedMs(startedAt: number): number {
  return Math.max(0, Math.round(performance.now() - startedAt));
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
