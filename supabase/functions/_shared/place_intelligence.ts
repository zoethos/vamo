import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const GLOBAL_ALIAS_PROMOTION_MIN_DISTINCT_USERS = 2;

export type PlaceFeatureType =
  | "country"
  | "region"
  | "locality"
  | "neighborhood"
  | "poi"
  | "landmark"
  | "address"
  | "unknown"
  | "any";

export type ProviderCacheIntent =
  | "seed_global"
  | "store_content"
  | "store_place_id"
  | "store_photo";

interface ProviderPolicy {
  canSeedGlobal: boolean;
  canStoreContent: boolean;
  canStorePlaceId: boolean;
  canStorePhoto: boolean;
}

const PROVIDER_POLICIES: Record<string, ProviderPolicy> = {
  fsq_os_places: {
    canSeedGlobal: true,
    canStoreContent: true,
    canStorePlaceId: true,
    canStorePhoto: true,
  },
  geonames: {
    canSeedGlobal: true,
    canStoreContent: true,
    canStorePlaceId: true,
    canStorePhoto: false,
  },
  wikidata: {
    canSeedGlobal: true,
    canStoreContent: true,
    canStorePlaceId: true,
    canStorePhoto: true,
  },
  foursquare_places_api: {
    canSeedGlobal: false,
    canStoreContent: false,
    canStorePlaceId: true,
    canStorePhoto: false,
  },
  google_places_api: {
    canSeedGlobal: false,
    canStoreContent: false,
    canStorePlaceId: true,
    canStorePhoto: false,
  },
  static_map: {
    canSeedGlobal: false,
    canStoreContent: true,
    canStorePlaceId: false,
    canStorePhoto: true,
  },
  user_observation: {
    canSeedGlobal: false,
    canStoreContent: false,
    canStorePlaceId: false,
    canStorePhoto: false,
  },
};

export interface PlaceAliasScope {
  countryCode: string;
  admin1: string;
  featureType: PlaceFeatureType;
}

export interface LocationObservationInput {
  userId: string;
  tripId?: string | null;
  query: string;
  canonicalId?: string | null;
  resolvedDisplayName?: string | null;
  resolvedFeatureType?: PlaceFeatureType | null;
  resolvedCountryCode?: string | null;
  resolvedLat?: number | null;
  resolvedLng?: number | null;
  provider?: string | null;
  providerPlaceId?: string | null;
  sourceAttribution?: string | null;
  trustedSourceMatch?: boolean;
  observationKind?:
    | "typed_destination"
    | "manual_find"
    | "create_trip_background"
    | "poi_selection"
    | "admin_seed";
  selected?: boolean;
  metadata?: Record<string, unknown>;
}

export function normalizePlaceAlias(raw: string | null | undefined): string {
  return (raw ?? "")
    .trim()
    .normalize("NFKC")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .slice(0, 160);
}

export function normalizeCountryCode(
  raw: string | null | undefined,
): string {
  const value = (raw ?? "").trim().toUpperCase();
  return /^[A-Z]{2}$/.test(value) ? value : "";
}

export function normalizeFeatureType(
  raw: string | null | undefined,
): PlaceFeatureType {
  const value = (raw ?? "").trim().toLowerCase();
  switch (value) {
    case "country":
    case "region":
    case "locality":
    case "neighborhood":
    case "poi":
    case "landmark":
    case "address":
    case "unknown":
    case "any":
      return value as PlaceFeatureType;
    default:
      return "any";
  }
}

export function normalizeAliasScope(args: {
  countryCode?: string | null;
  admin1?: string | null;
  featureType?: string | null;
}): PlaceAliasScope {
  return {
    countryCode: normalizeCountryCode(args.countryCode),
    admin1: normalizePlaceAlias(args.admin1).slice(0, 80),
    featureType: normalizeFeatureType(args.featureType),
  };
}

export function aliasCollisionKey(args: {
  aliasNorm: string;
  canonicalId: string;
  scope: PlaceAliasScope;
}): string {
  return [
    args.aliasNorm,
    args.scope.countryCode,
    args.scope.admin1,
    args.scope.featureType,
    args.canonicalId,
  ].join("|");
}

export function assertPlaceProviderPolicy(
  provider: string,
  intent: ProviderCacheIntent,
): void {
  const policy = PROVIDER_POLICIES[provider];
  if (!policy) throw new Error(`unknown_place_provider:${provider}`);

  const allowed = intent === "seed_global"
    ? policy.canSeedGlobal
    : intent === "store_content"
    ? policy.canStoreContent
    : intent === "store_place_id"
    ? policy.canStorePlaceId
    : policy.canStorePhoto;
  if (!allowed) {
    throw new Error(`place_provider_policy_denied:${provider}:${intent}`);
  }
}

export async function hashPlaceQuery(raw: string): Promise<string> {
  const normalized = normalizePlaceAlias(raw);
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(normalized),
  );
  return Array.from(new Uint8Array(bytes))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function runInBackground(
  promise: Promise<unknown>,
  label: string,
): void {
  const guarded = promise.catch((error) => {
    console.error(`${label} failed`, error);
  });
  const runtime = (globalThis as {
    EdgeRuntime?: { waitUntil?: (task: Promise<unknown>) => void };
  }).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(guarded);
    return;
  }
  void guarded;
}

export async function recordLocationObservation(
  supabase: SupabaseClient,
  input: LocationObservationInput,
): Promise<void> {
  const queryNorm = normalizePlaceAlias(input.query);
  if (queryNorm.length < 2) return;
  if (input.provider && input.providerPlaceId) {
    assertPlaceProviderPolicy(input.provider, "store_place_id");
  }
  const queryHash = await hashPlaceQuery(queryNorm);
  const { error } = await supabase.from("location_observations").insert({
    user_id: input.userId,
    trip_id: input.tripId ?? null,
    query_hash: queryHash,
    query_norm: queryNorm,
    canonical_id: input.canonicalId ?? null,
    resolved_display_name: input.resolvedDisplayName ?? null,
    resolved_feature_type: input.resolvedFeatureType ?? null,
    resolved_country_code: normalizeCountryCode(input.resolvedCountryCode) ||
      null,
    resolved_latitude: finiteNumber(input.resolvedLat),
    resolved_longitude: finiteNumber(input.resolvedLng),
    provider: input.provider ?? null,
    provider_place_id: input.providerPlaceId ?? null,
    source_attribution: input.sourceAttribution ?? null,
    trusted_source_match: input.trustedSourceMatch === true,
    observation_kind: input.observationKind ?? "typed_destination",
    selected: input.selected !== false,
    metadata: input.metadata ?? {},
  });
  if (error) throw error;

  if (input.canonicalId != null) {
    const { error: promoteError } = await supabase.rpc(
      "promote_location_aliases",
      { p_min_distinct_users: GLOBAL_ALIAS_PROMOTION_MIN_DISTINCT_USERS },
    );
    if (promoteError) throw promoteError;
  }
}

function finiteNumber(raw: number | null | undefined): number | null {
  return typeof raw === "number" && Number.isFinite(raw) ? raw : null;
}
