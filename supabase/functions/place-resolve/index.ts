// Place resolver gateway.
//
// Auth: caller JWT required. Cache tables stay service-role only.
// Priority: hashed resolution cache -> promoted scoped aliases -> no result.
// Observation writes and promotion attempts run in the background.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  hashPlaceQuery,
  normalizeAliasScope,
  normalizeFeatureType,
  normalizePlaceAlias,
  type PlaceAliasScope,
  type PlaceFeatureType,
  recordLocationObservation,
  runInBackground,
} from "../_shared/place_intelligence.ts";

interface PlaceResolveInput {
  query: string;
  tripId?: string | null;
  countryCode?: string | null;
  featureType?: PlaceFeatureType | null;
  observationKind?:
    | "typed_destination"
    | "manual_find"
    | "create_trip_background"
    | "poi_selection";
}

interface CanonicalRow {
  id: string;
  display_name: string;
  feature_type: PlaceFeatureType;
  country_code?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  attribution: string;
  confidence?: number | null;
}

interface CacheRow {
  canonical_id: string;
  source_provider: string;
  attribution: string;
  confidence?: number | null;
  expires_at: string;
  scope_country_code?: string | null;
  scope_feature_type?: string | null;
}

interface AliasRow {
  canonical_id: string;
  scope_country_code?: string | null;
  scope_feature_type?: string | null;
  weight?: number | null;
  confidence?: number | null;
  trusted_source_match?: boolean | null;
  distinct_user_count?: number | null;
  attribution: string;
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

  if (input.tripId) {
    const { data: trip, error: tripError } = await userClient
      .from("trips")
      .select("id")
      .eq("id", input.tripId)
      .maybeSingle();
    if (tripError || !trip) return json({ error: "trip_not_found" }, 404);
  }

  const serviceClient = createClient(supabaseUrl, serviceKey);
  const aliasNorm = normalizePlaceAlias(input.query);
  const scope = normalizeAliasScope({
    countryCode: input.countryCode,
    featureType: input.featureType,
  });
  const queryHash = await hashPlaceQuery(aliasNorm);

  const cached = await readCachedResolution(serviceClient, queryHash, scope);
  if (cached) {
    scheduleObservation(serviceClient, {
      input,
      userId: user.id,
      canonical: cached.canonical,
      sourceProvider: cached.sourceProvider,
      sourceAttribution: cached.attribution,
      trustedSourceMatch: true,
    });
    return json({
      available: true,
      source: "cache",
      ...payloadForCanonical(cached.canonical, cached.confidence),
    });
  }

  const aliased = await readAliasResolution(serviceClient, aliasNorm, scope);
  if (aliased) {
    scheduleObservation(serviceClient, {
      input,
      userId: user.id,
      canonical: aliased.canonical,
      sourceProvider: "user_observation",
      sourceAttribution: aliased.attribution,
      trustedSourceMatch: aliased.trustedSourceMatch,
    });
    return json({
      available: true,
      source: "alias",
      ...payloadForCanonical(aliased.canonical, aliased.confidence),
    });
  }

  scheduleObservation(serviceClient, {
    input,
    userId: user.id,
    sourceProvider: "user_observation",
    sourceAttribution: "Vamo unresolved place observation",
    trustedSourceMatch: false,
  });
  return json({ available: false, reason: "cache_miss" });
});

async function readInput(req: Request): Promise<PlaceResolveInput | null> {
  try {
    const body = await req.json();
    if (body == null || typeof body !== "object") return null;
    const row = body as Record<string, unknown>;
    const query = stringValue(row.query) ?? stringValue(row.destination);
    if (!query || query.length < 2 || query.length > 160) return null;
    return {
      query,
      tripId: stringValue(row.trip_id) ?? stringValue(row.tripId) ?? null,
      countryCode: stringValue(row.country_code) ??
        stringValue(row.countryCode) ?? null,
      featureType: normalizeFeatureType(
        stringValue(row.feature_type) ?? stringValue(row.featureType),
      ),
      observationKind: observationKindValue(row.observation_kind) ??
        observationKindValue(row.observationKind) ?? "typed_destination",
    };
  } catch {
    return null;
  }
}

async function readCachedResolution(
  supabase: SupabaseClient,
  queryHash: string,
  scope: PlaceAliasScope,
): Promise<
  | {
    canonical: CanonicalRow;
    sourceProvider: string;
    attribution: string;
    confidence: number | null;
  }
  | null
> {
  const { data, error } = await supabase
    .from("location_resolution_cache")
    .select(
      "canonical_id,source_provider,attribution,confidence,expires_at,scope_country_code,scope_feature_type",
    )
    .eq("query_hash", queryHash)
    .in("scope_country_code", [scope.countryCode, ""])
    .in("scope_feature_type", [scope.featureType, "any"])
    .order("confidence", { ascending: false })
    .limit(5);
  if (error || !Array.isArray(data)) return null;

  for (const row of data as CacheRow[]) {
    if (Date.parse(row.expires_at) <= Date.now()) continue;
    const canonical = await readCanonical(supabase, row.canonical_id);
    if (!canonical) continue;
    return {
      canonical,
      sourceProvider: row.source_provider,
      attribution: row.attribution,
      confidence: row.confidence ?? null,
    };
  }
  return null;
}

async function readAliasResolution(
  supabase: SupabaseClient,
  aliasNorm: string,
  scope: PlaceAliasScope,
): Promise<
  | {
    canonical: CanonicalRow;
    attribution: string;
    confidence: number | null;
    trustedSourceMatch: boolean;
  }
  | null
> {
  const { data, error } = await supabase
    .from("location_aliases")
    .select(
      "canonical_id,scope_country_code,scope_feature_type,weight,confidence,trusted_source_match,distinct_user_count,attribution",
    )
    .eq("alias_norm", aliasNorm)
    .eq("promotion_state", "promoted")
    .limit(20);
  if (error || !Array.isArray(data)) return null;

  const ranked = (data as AliasRow[])
    .map((row) => ({ row, score: aliasScore(row, scope) }))
    .sort((a, b) => b.score - a.score);
  for (const candidate of ranked) {
    const canonical = await readCanonical(supabase, candidate.row.canonical_id);
    if (!canonical) continue;
    return {
      canonical,
      attribution: candidate.row.attribution,
      confidence: candidate.row.confidence ?? null,
      trustedSourceMatch: candidate.row.trusted_source_match === true,
    };
  }
  return null;
}

async function readCanonical(
  supabase: SupabaseClient,
  canonicalId: string,
): Promise<CanonicalRow | null> {
  const { data, error } = await supabase
    .from("location_canonicals")
    .select(
      "id,display_name,feature_type,country_code,latitude,longitude,attribution,confidence",
    )
    .eq("id", canonicalId)
    .neq("promotion_state", "retired")
    .maybeSingle();
  if (error || !data) return null;
  return data as CanonicalRow;
}

function aliasScore(row: AliasRow, scope: PlaceAliasScope): number {
  const country = row.scope_country_code ?? "";
  const feature = row.scope_feature_type ?? "any";
  const countryScore = country === scope.countryCode
    ? 5
    : country === ""
    ? 1
    : 0;
  const featureScore = feature === scope.featureType
    ? 3
    : feature === "any"
    ? 1
    : 0;
  return countryScore + featureScore + (row.weight ?? 0) +
    ((row.confidence ?? 0) * 2) + ((row.distinct_user_count ?? 0) * 0.1);
}

function scheduleObservation(
  supabase: SupabaseClient,
  args: {
    input: PlaceResolveInput;
    userId: string;
    canonical?: CanonicalRow;
    sourceProvider: string;
    sourceAttribution: string;
    trustedSourceMatch: boolean;
  },
): void {
  runInBackground(
    recordLocationObservation(supabase, {
      userId: args.userId,
      tripId: args.input.tripId,
      query: args.input.query,
      canonicalId: args.canonical?.id ?? null,
      resolvedDisplayName: args.canonical?.display_name ?? null,
      resolvedFeatureType: args.canonical?.feature_type ?? null,
      resolvedCountryCode: args.canonical?.country_code ?? null,
      resolvedLat: args.canonical?.latitude ?? null,
      resolvedLng: args.canonical?.longitude ?? null,
      provider: args.sourceProvider,
      sourceAttribution: args.sourceAttribution,
      trustedSourceMatch: args.trustedSourceMatch,
      observationKind: args.input.observationKind,
      metadata: { resolver: "place-resolve" },
    }),
    "place-resolve observation",
  );
}

function payloadForCanonical(
  canonical: CanonicalRow,
  confidence: number | null,
): Record<string, unknown> {
  return {
    canonical_id: canonical.id,
    title: canonical.display_name,
    feature_type: canonical.feature_type,
    country_code: canonical.country_code ?? null,
    lat: canonical.latitude ?? null,
    lng: canonical.longitude ?? null,
    attribution: canonical.attribution,
    confidence: confidence ?? canonical.confidence ?? null,
  };
}

function stringValue(raw: unknown): string | undefined {
  if (typeof raw !== "string") return undefined;
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function observationKindValue(
  raw: unknown,
): PlaceResolveInput["observationKind"] | undefined {
  switch (stringValue(raw)) {
    case "typed_destination":
    case "manual_find":
    case "create_trip_background":
    case "poi_selection":
      return stringValue(raw) as PlaceResolveInput["observationKind"];
    default:
      return undefined;
  }
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
