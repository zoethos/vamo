/**
 * FSQ OS Places catalog acquisition boundary (IP-18.8.10).
 *
 * The only module allowed to perform provider-facing HTTP for FSQ snapshot
 * acquisition. Tokens must come from server/job secrets at runtime only.
 */

export const FSQ_OS_PLACES_CATALOG_TOKEN_ENV = "FSQ_OS_PLACES_CATALOG_TOKEN" as const;
export const FSQ_OS_PLACES_DEFAULT_ATTRIBUTION = "FSQ Open Source Places" as const;
export const FSQ_OS_PLACES_DEFAULT_PROVENANCE_URL =
  "https://places.foursquare.com/products/open-source-places" as const;
export const FSQ_OS_PLACES_DEFAULT_CATALOG_BASE_URL =
  "https://catalog.foursquare.com/os-places/v1/places" as const;

export const FSQ_ACQUISITION_ALLOWED_COUNTRIES = [
  "italy",
  "france",
  "germany",
  "spain",
  "portugal",
  "netherlands",
  "belgium",
  "austria",
  "switzerland",
  "poland",
  "greece",
  "ireland"
] as const;

export const FSQ_ACQUISITION_ALLOWED_CATEGORIES = [
  "poi",
  "landmark",
  "restaurant",
  "transport"
] as const;

export const FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE = 250;

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
  const blocks: string[] = [];
  const countries = [...new Set(input.countries.map((entry) => entry.trim().toLowerCase()))].sort();
  const categories = [...new Set(input.categories.map((entry) => entry.trim().toLowerCase()))].sort();

  if (countries.length === 0) {
    blocks.push("countries_required");
  }
  if (categories.length === 0) {
    blocks.push("categories_required");
  }

  for (const country of countries) {
    if (!(FSQ_ACQUISITION_ALLOWED_COUNTRIES as readonly string[]).includes(country)) {
      blocks.push(`country_out_of_bounds:${country}`);
    }
  }
  for (const category of categories) {
    if (!(FSQ_ACQUISITION_ALLOWED_CATEGORIES as readonly string[]).includes(category)) {
      blocks.push(`category_out_of_bounds:${category}`);
    }
  }

  const maxRowsPerScope = input.maxRowsPerScope ?? FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE;
  if (!Number.isInteger(maxRowsPerScope) || maxRowsPerScope < 1 || maxRowsPerScope > 1000) {
    blocks.push("max_rows_per_scope_out_of_bounds");
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const scopes = countries.flatMap((country) =>
    categories.map((category) => ({
      country,
      geography: country,
      category
    }))
  );

  return {
    ok: true,
    plan: {
      countries,
      categories,
      scopes,
      maxRowsPerScope
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
  token?: string;
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

  const token = input.token?.trim();
  if (!token) {
    return { ok: false, blocks: ["catalog_token_missing"] };
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
          authorization: `Bearer ${token}`,
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
