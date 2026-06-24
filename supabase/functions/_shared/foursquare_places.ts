const FOURSQUARE_SEARCH = "https://places-api.foursquare.com/places/search";
const FOURSQUARE_API_VERSION = "2025-06-17";

export interface FoursquarePlaceSearchRequest {
  apiKey: string;
  near?: string | null;
  lat?: number | null;
  lng?: number | null;
  radius?: number | string | null;
  query?: string | null;
  category?: string | null;
  limit?: number;
  fields?: string[];
}

export class FoursquareHttpError extends Error {
  constructor(readonly status: number) {
    super(`Foursquare search failed: ${status}`);
    this.name = "FoursquareHttpError";
  }
}

export async function searchFoursquarePlaces(
  request: FoursquarePlaceSearchRequest,
): Promise<unknown> {
  const url = new URL(FOURSQUARE_SEARCH);
  if (request.near?.trim()) {
    url.searchParams.set("near", request.near.trim());
  } else if (request.lat != null && request.lng != null) {
    url.searchParams.set("ll", `${request.lat},${request.lng}`);
    if (request.radius != null) {
      url.searchParams.set("radius", `${request.radius}`);
    }
  } else {
    throw new FoursquareHttpError(400);
  }

  url.searchParams.set("limit", `${request.limit ?? 12}`);
  url.searchParams.set(
    "fields",
    (request.fields ?? defaultFoursquareFields()).join(","),
  );
  const searchQuery = request.query?.trim() ||
    queryForFoursquareCategory(request.category);
  if (searchQuery) url.searchParams.set("query", searchQuery);

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${request.apiKey}`,
      Accept: "application/json",
      "X-Places-Api-Version": FOURSQUARE_API_VERSION,
    },
  });
  if (!response.ok) {
    throw new FoursquareHttpError(response.status);
  }
  return await response.json();
}

export function classifyFoursquareProviderError(error: unknown): string {
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

export function queryForFoursquareCategory(
  category: string | null | undefined,
): string | null {
  switch (category) {
    case "food":
      return "restaurant";
    case "lodging":
      return "hotel";
    case "attraction":
      return "attraction";
    case "museum":
      return "museum";
    case "nature":
      return "park";
    case "nightlife":
      return "bar";
    case "shopping":
      return "shopping";
    case "transport":
      return "station";
    default:
      return null;
  }
}

export function photoUrlFromFoursquarePhotos(
  raw: unknown,
  size = "300x300",
): string | undefined {
  if (!Array.isArray(raw) || raw.length === 0) return undefined;
  for (const entry of raw) {
    if (entry == null || typeof entry !== "object") continue;
    const photo = entry as Record<string, unknown>;
    const directUrl = stringValue(photo.url);
    if (directUrl) return directUrl;
    const prefix = stringValue(photo.prefix);
    const suffix = stringValue(photo.suffix);
    if (prefix && suffix) return `${prefix}${size}${suffix}`;
  }
  return undefined;
}

export function addressFromFoursquareLocation(
  raw: unknown,
): string | undefined {
  if (raw == null || typeof raw !== "object") return undefined;
  const location = raw as Record<string, unknown>;
  const joined = [
    location.address,
    location.locality,
    location.region,
    location.country,
  ]
    .map(stringValue)
    .filter((value): value is string => value != null)
    .join(", ");
  return stringValue(location.formatted_address) ??
    stringValue(location.address) ??
    (joined.length > 0 ? joined : undefined);
}

function defaultFoursquareFields(): string[] {
  return [
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
  ];
}

function stringValue(raw: unknown): string | undefined {
  if (typeof raw !== "string") return undefined;
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}
