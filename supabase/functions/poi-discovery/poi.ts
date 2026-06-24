export type PoiCategory =
  | "food"
  | "lodging"
  | "attraction"
  | "museum"
  | "nature"
  | "nightlife"
  | "shopping"
  | "transport"
  | "other";

export interface Poi {
  id: string;
  name: string;
  category: PoiCategory;
  lat: number;
  lng: number;
  address?: string;
  distanceM?: number;
  about?: string;
  website?: string;
  phone?: string;
  hours?: string;
  rating?: number;
  priceLevel?: number;
  photoUrl?: string;
  source: "foursquare";
  providerPlaceId: string;
}

export function normalizeFoursquarePlaces(raw: unknown): Poi[] {
  const rows = Array.isArray((raw as { results?: unknown[] })?.results)
    ? (raw as { results: unknown[] }).results
    : Array.isArray(raw)
    ? raw as unknown[]
    : [];

  return rows
    .map(normalizeFoursquarePlace)
    .filter((poi): poi is Poi => poi != null);
}

function normalizeFoursquarePlace(raw: unknown): Poi | null {
  if (raw == null || typeof raw !== "object") return null;
  const row = raw as Record<string, unknown>;
  const id = stringValue(row.fsq_place_id) ?? stringValue(row.id);
  const name = stringValue(row.name);
  const lat = numberValue(row.latitude);
  const lng = numberValue(row.longitude);
  if (!id || !name || lat == null || lng == null) return null;

  const poi: Poi = {
    id: id,
    providerPlaceId: id,
    name,
    category: bucketForCategories(row.categories, row.fsq_category_labels),
    lat,
    lng,
    source: "foursquare",
  };
  const address = addressFromFoursquareLocation(row.location);
  const distanceM = roundOrUndefined(numberValue(row.distance));
  const about = stringValue(row.description);
  const website = stringValue(row.website);
  const phone = stringValue(row.tel);
  const hours = hoursLabel(row.hours);
  const rating = numberValue(row.rating);
  const priceLevel = roundOrUndefined(numberValue(row.price));
  const photoUrl = photoUrlFromFoursquarePhotos(row.photos);
  if (address) poi.address = address;
  if (distanceM != null) poi.distanceM = distanceM;
  if (about) poi.about = about;
  if (website) poi.website = website;
  if (phone) poi.phone = phone;
  if (hours) poi.hours = hours;
  if (rating != null) poi.rating = rating;
  if (priceLevel != null) poi.priceLevel = priceLevel;
  if (photoUrl) poi.photoUrl = photoUrl;
  return poi;
}

export const queryForCategory = queryForFoursquareCategory;

function bucketForCategories(
  categoriesRaw: unknown,
  labelsRaw: unknown,
): PoiCategory {
  const labels: string[] = [];
  if (Array.isArray(categoriesRaw)) {
    for (const category of categoriesRaw) {
      if (category != null && typeof category === "object") {
        const name = stringValue((category as Record<string, unknown>).name);
        if (name) labels.push(name);
      }
    }
  }
  if (Array.isArray(labelsRaw)) {
    for (const label of labelsRaw) {
      const value = stringValue(label);
      if (value) labels.push(value);
    }
  }

  const text = labels.join(" ").toLowerCase();
  if (/(restaurant|cafe|coffee|barbecue|pizza|bakery|food|dining)/.test(text)) {
    return "food";
  }
  if (/(hotel|lodging|hostel|resort|motel)/.test(text)) return "lodging";
  if (/(museum|gallery)/.test(text)) return "museum";
  if (/(park|garden|beach|trail|mountain|nature)/.test(text)) return "nature";
  if (/(bar|pub|club|nightlife)/.test(text)) return "nightlife";
  if (/(shop|store|mall|market)/.test(text)) return "shopping";
  if (/(station|airport|train|bus|transport|subway|metro)/.test(text)) {
    return "transport";
  }
  if (
    /(landmark|monument|historic|attraction|sight|temple|church)/.test(text)
  ) {
    return "attraction";
  }
  return "other";
}

function hoursLabel(raw: unknown): string | undefined {
  if (raw == null || typeof raw !== "object") return undefined;
  const hours = raw as Record<string, unknown>;
  const display = stringValue(hours.display) ?? stringValue(hours.status);
  if (display) return display;
  if (hours.open_now === true) return "Open now";
  if (hours.open_now === false) return "Closed now";
  return undefined;
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

function roundOrUndefined(value: number | undefined): number | undefined {
  return value == null ? undefined : Math.round(value);
}
import {
  addressFromFoursquareLocation,
  photoUrlFromFoursquarePhotos,
  queryForFoursquareCategory,
} from "../_shared/foursquare_places.ts";
