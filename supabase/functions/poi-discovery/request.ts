export interface PoiInput {
  mode: "nearby" | "search";
  tripId: string;
  lat: number;
  lng: number;
  query: string | null;
  regionBias: string | null;
  category: string | null;
  radius: number;
  sessionId: string | null;
}

const DEFAULT_RADIUS_M = 1200;
const MAX_RADIUS_M = 5000;

export function readPoiInputFromBody(body: unknown): PoiInput | null {
  const record = isRecord(body) ? body : null;
  const tripId = stringValue(record?.trip_id);
  const mode = stringValue(record?.mode) === "search" ? "search" : "nearby";
  const query = stringValue(record?.query) ?? null;
  const regionBias = stringValue(record?.regionBias) ??
    stringValue(record?.region_bias) ?? null;
  const lat = numberValue(record?.lat);
  const lng = numberValue(record?.lng);
  if (!tripId) return null;
  if (mode === "nearby") {
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  }
  if (mode === "search" && (!query || query.length < 3)) return null;
  const radius = clampRadius(numberValue(record?.radius));
  return {
    mode,
    tripId,
    lat: lat ?? 0,
    lng: lng ?? 0,
    query,
    regionBias,
    category: stringValue(record?.category) ?? null,
    radius,
    sessionId: stringValue(record?.session_id) ?? null,
  };
}

export function cacheKeyForPoiInput(
  service: string,
  provider: string,
  input: PoiInput,
  regionBias: string | null,
): { cacheKey: string; geohash: string; category: string; queryKey: string } {
  const geohash = input.mode === "nearby"
    ? encodeGeohash(input.lat, input.lng, 6)
    : `near:${slugKey(regionBias ?? "global")}`;
  const category = normalizeCategory(input.category);
  const queryKey = normalizeQuery(input.query) ?? "any";
  return {
    cacheKey:
      `${service}:${provider}:${input.mode}:${geohash}:${category}:${queryKey}`,
    geohash,
    category,
    queryKey,
  };
}

export function normalizeCategory(raw: string | null): string {
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

export function normalizeQuery(raw: string | null): string | null {
  const value = raw?.trim().toLowerCase().replace(/\s+/g, " ") ?? "";
  return value.length > 0 ? value.slice(0, 80) : null;
}

export function slugKey(raw: string): string {
  return raw.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(
    /^-|-$/g,
    "",
  ).slice(0, 80) || "global";
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

function isRecord(raw: unknown): raw is Record<string, unknown> {
  return typeof raw === "object" && raw !== null && !Array.isArray(raw);
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
