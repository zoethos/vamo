/**
 * FSQ OS Places catalog acquisition boundary (IP-18.8.10).
 *
 * The only module allowed to perform provider-facing HTTP for FSQ snapshot
 * acquisition. Service API keys must come from server/job secrets at runtime only.
 */

import {
  FSQ_ACQUISITION_ALLOWED_CATEGORIES,
  FSQ_ACQUISITION_ALLOWED_COUNTRIES,
  FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE,
  validateFsqAcquisitionBounds as validateCoreFsqAcquisitionBounds
} from "../../../core/src/fsq-acquisition-scope.js";

export {
  FSQ_ACQUISITION_ALLOWED_CATEGORIES,
  FSQ_ACQUISITION_ALLOWED_COUNTRIES,
  FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE
} from "../../../core/src/fsq-acquisition-scope.js";

/** Canonical name for the Foursquare credential used by the catalog adapter. */
export const FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY_ENV =
  "FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY" as const;

/**
 * @deprecated Use FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY_ENV. Retained only so
 * existing trusted job configuration can be migrated without an outage.
 */
export const FSQ_OS_PLACES_CATALOG_TOKEN_ENV = "FSQ_OS_PLACES_CATALOG_TOKEN" as const;

export const FSQ_OS_PLACES_DEFAULT_ATTRIBUTION = "FSQ Open Source Places" as const;
export const FSQ_OS_PLACES_DEFAULT_PROVENANCE_URL =
  "https://places.foursquare.com/products/open-source-places" as const;
export const FSQ_OS_PLACES_DEFAULT_CATALOG_BASE_URL =
  "https://catalog.foursquare.com/os-places/v1/places" as const;

export type FsqCatalogFetchFn = (input: {
  url: string;
  headers: Record<string, string>;
}) => Promise<{ ok: boolean; status: number; body: string }>;

export interface FsqCatalogPlaceRecord {
  fsqPlaceId: string;
  name: string;
  latitude: number;
  longitude: number;
  geography: string;
  category: string;
}

export interface FsqCatalogAcquirePlan {
  countries: string[];
  categories: string[];
  scopes: Array<{ geography: string; category: string; country: string }>;
  maxRowsPerScope: number;
}

export type FsqCatalogAcquireResult =
  | {
      ok: true;
      preview: true;
      plan: FsqCatalogAcquirePlan;
      normalizedJsonl: string;
      providerRecordCount: number;
    }
  | {
      ok: true;
      preview: false;
      plan: FsqCatalogAcquirePlan;
      normalizedJsonl: string;
      providerRecordCount: number;
    }
  | { ok: false; blocks: string[] };

export function validateFsqAcquisitionBounds(input: {
  countries: readonly string[];
  categories: readonly string[];
  maxRowsPerScope?: number;
}): { ok: true; plan: FsqCatalogAcquirePlan } | { ok: false; blocks: string[] } {
  const bounds = validateCoreFsqAcquisitionBounds(input);
  if (!bounds.ok) {
    return bounds;
  }

  const scopes = bounds.plan.countries.flatMap((country) =>
    bounds.plan.categories.map((category) => ({
      country,
      geography: country,
      category
    }))
  );

  return {
    ok: true,
    plan: {
      ...bounds.plan,
      scopes
    }
  };
}

export function normalizeFsqCatalogPlaceRecord(
  record: FsqCatalogPlaceRecord,
  attribution = FSQ_OS_PLACES_DEFAULT_ATTRIBUTION
): Record<string, unknown> {
  return {
    source_row_id: 0,
    source: {
      id: `fsq_${record.fsqPlaceId}`,
      name: record.name,
      latitude: record.latitude,
      longitude: record.longitude
    },
    scope: {
      geography: record.geography,
      category: record.category
    },
    attribution
  };
}

export function serializeNormalizedFsqCatalogRecords(
  records: readonly Record<string, unknown>[]
): string {
  const lines = records.map((record) => JSON.stringify(record));
  return lines.length > 0 ? `${lines.join("\n")}\n` : "";
}

export function parseFsqCatalogResponseBody(body: string): FsqCatalogPlaceRecord[] {
  const payload = JSON.parse(body) as { places?: unknown };
  if (!payload.places || !Array.isArray(payload.places)) {
    return [];
  }
  const records: FsqCatalogPlaceRecord[] = [];
  for (const entry of payload.places) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      continue;
    }
    const row = entry as Record<string, unknown>;
    const fsqPlaceId = readString(row.fsq_place_id ?? row.fsqPlaceId);
    const name = readString(row.name);
    const latitude = readNumber(row.latitude);
    const longitude = readNumber(row.longitude);
    const geography = readString(row.geography);
    const category = readString(row.category)?.toLowerCase();
    if (!fsqPlaceId || !name || latitude === null || longitude === null || !geography || !category) {
      continue;
    }
    records.push({
      fsqPlaceId,
      name,
      latitude,
      longitude,
      geography,
      category
    });
  }
  return records;
}

export async function acquireFsqOsPlacesCatalog(input: {
  countries: readonly string[];
  categories: readonly string[];
  maxRowsPerScope?: number;
  preview?: boolean;
  serviceApiKey?: string;
  catalogBaseUrl?: string;
  fetchFn?: FsqCatalogFetchFn;
  fixtureRecords?: readonly FsqCatalogPlaceRecord[];
}): Promise<FsqCatalogAcquireResult> {
  const bounds = validateFsqAcquisitionBounds(input);
  if (!bounds.ok) {
    return { ok: false, blocks: bounds.blocks };
  }

  if (input.preview) {
    return {
      ok: true,
      preview: true,
      plan: bounds.plan,
      normalizedJsonl: "",
      providerRecordCount: 0
    };
  }

  const serviceApiKey = input.serviceApiKey?.trim();
  if (!serviceApiKey) {
    return { ok: false, blocks: ["service_api_key_missing"] };
  }

  const records: FsqCatalogPlaceRecord[] = [];
  const fetchFn = input.fetchFn ?? defaultCatalogFetch;
  const catalogBaseUrl = input.catalogBaseUrl ?? FSQ_OS_PLACES_DEFAULT_CATALOG_BASE_URL;

  if (input.fixtureRecords) {
    records.push(...filterFixtureRecords(input.fixtureRecords, bounds.plan));
  } else {
    for (const scope of bounds.plan.scopes) {
      const url = `${catalogBaseUrl}?country=${encodeURIComponent(scope.country)}&category=${encodeURIComponent(scope.category)}&limit=${bounds.plan.maxRowsPerScope}`;
      const response = await fetchFn({
        url,
        headers: {
          authorization: `Bearer ${serviceApiKey}`,
          accept: "application/json"
        }
      });
      if (!response.ok) {
        return { ok: false, blocks: [`catalog_fetch_failed:${scope.country}:${scope.category}:${response.status}`] };
      }
      records.push(...parseFsqCatalogResponseBody(response.body));
    }
  }

  const normalized = records
    .map((record) => normalizeFsqCatalogPlaceRecord(record))
    .sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
  const normalizedJsonl = serializeNormalizedFsqCatalogRecords(normalized);

  return {
    ok: true,
    preview: false,
    plan: bounds.plan,
    normalizedJsonl,
    providerRecordCount: records.length
  };
}

function filterFixtureRecords(
  fixtureRecords: readonly FsqCatalogPlaceRecord[],
  plan: FsqCatalogAcquirePlan
): FsqCatalogPlaceRecord[] {
  const perScope = new Map<string, number>();
  const selected: FsqCatalogPlaceRecord[] = [];
  for (const record of fixtureRecords) {
    const matchingScope = plan.scopes.find((scope) => geographyMatchesScope(record, scope));
    if (!matchingScope) {
      continue;
    }
    const scopeKey = `${matchingScope.country}:${matchingScope.category}`;
    const count = perScope.get(scopeKey) ?? 0;
    if (count >= plan.maxRowsPerScope) {
      continue;
    }
    perScope.set(scopeKey, count + 1);
    selected.push(record);
  }
  return selected.sort((left, right) =>
    `${left.geography}:${left.category}:${left.fsqPlaceId}`.localeCompare(
      `${right.geography}:${right.category}:${right.fsqPlaceId}`
    )
  );
}

function geographyMatchesScope(
  record: FsqCatalogPlaceRecord,
  scope: { country: string; category: string }
): boolean {
  if (record.category !== scope.category) {
    return false;
  }
  const geography = record.geography.toLowerCase();
  return geography === scope.country || geography.endsWith(`-${scope.country}`);
}

async function defaultCatalogFetch(input: {
  url: string;
  headers: Record<string, string>;
}): Promise<{ ok: boolean; status: number; body: string }> {
  const response = await fetch(input.url, { headers: input.headers });
  return {
    ok: response.ok,
    status: response.status,
    body: await response.text()
  };
}

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function readNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}
