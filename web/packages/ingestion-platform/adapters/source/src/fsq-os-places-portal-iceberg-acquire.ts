/**
 * FSQ OS Places Portal / Iceberg acquisition boundary (IP-18.8.16).
 *
 * The only module allowed to talk to the FSQ Places Portal Iceberg catalog for
 * snapshot acquisition. Portal access tokens must come from server/job secrets
 * at runtime only. Never disable TLS verification from this adapter.
 */

import {
  FSQ_ACQUISITION_ALLOWED_CATEGORIES,
  FSQ_ACQUISITION_ALLOWED_COUNTRIES,
  FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE,
  validateFsqAcquisitionBounds as validateCoreFsqAcquisitionBounds
} from "../../../core/src/fsq-acquisition-scope.js";
import {
  classifyFsqPlaceConsumerCategory,
  type FsqSourceTaxonomyMapping
} from "../../../core/src/fsq-source-taxonomy.js";
import { validateFsqPortalAccessTokenExpiry } from "../../../core/src/fsq-portal-access-token.js";

export {
  FSQ_ACQUISITION_ALLOWED_CATEGORIES,
  FSQ_ACQUISITION_ALLOWED_COUNTRIES,
  FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE
} from "../../../core/src/fsq-acquisition-scope.js";

/** Retained for potential future live Places API use — not required for snapshots. */
export const FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY_ENV =
  "FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY" as const;

export const FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN_ENV =
  "FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN" as const;

export const FSQ_OS_PLACES_DEFAULT_ATTRIBUTION = "FSQ Open Source Places" as const;
export const FSQ_OS_PLACES_DEFAULT_PROVENANCE_URL =
  "https://places.foursquare.com/products/open-source-places" as const;

export const FSQ_OS_PLACES_PORTAL_ICEBERG_ENDPOINT =
  "https://catalog.h3-hub.foursquare.com/iceberg" as const;
export const FSQ_OS_PLACES_PORTAL_ICEBERG_TABLE = "places.datasets.places_os" as const;
export const FSQ_OS_PLACES_PORTAL_ICEBERG_CATALOG_ALIAS = "places" as const;

export const FSQ_OS_PLACES_PORTAL_DEFAULT_QUERY_TIMEOUT_MS = 120_000;

/** Country plan keys → ISO-3166 alpha-2 codes used by FSQ OS Places. */
export const FSQ_OS_PLACES_COUNTRY_ISO: Readonly<Record<string, string>> = {
  italy: "IT",
  france: "FR",
  germany: "DE",
  spain: "ES",
  portugal: "PT",
  netherlands: "NL",
  belgium: "BE",
  austria: "AT",
  switzerland: "CH",
  poland: "PL",
  greece: "GR",
  ireland: "IE"
};

export interface FsqPortalPlaceRecord {
  fsqPlaceId: string;
  name: string;
  latitude: number;
  longitude: number;
  geography: string;
  category: string;
  providerCategoryIds?: string[];
  providerCategoryLabels?: string[];
}

export interface FsqPortalAcquirePlan {
  countries: string[];
  categories: string[];
  scopes: Array<{ geography: string; category: string; country: string }>;
  maxRowsPerScope: number;
}

export type FsqPortalAcquireResult =
  | {
      ok: true;
      preview: true;
      plan: FsqPortalAcquirePlan;
      normalizedJsonl: string;
      providerRecordCount: number;
    }
  | {
      ok: true;
      preview: false;
      plan: FsqPortalAcquirePlan;
      normalizedJsonl: string;
      providerRecordCount: number;
    }
  | { ok: false; blocks: string[] };

export interface FsqPortalIcebergQueryRow {
  fsqPlaceId: string;
  name: string;
  latitude: number;
  longitude: number;
  countryIso: string;
  locality?: string;
  providerCategoryIds: string[];
  providerCategoryLabels: string[];
}

/**
 * Narrow injectable DuckDB seam for tests and trusted workers.
 * Production runners come from fsq-os-places-portal-iceberg-duckdb.ts
 * (CLI/job only — never imported by Console).
 */
export interface FsqPortalIcebergDuckDbRunner {
  queryCountryPlaces(input: {
    portalAccessToken: string;
    endpoint: string;
    table: string;
    countryIso: string;
    limit: number;
    timeoutMs: number;
  }): Promise<
    | { ok: true; rows: FsqPortalIcebergQueryRow[] }
    | { ok: false; block: string }
  >;
}

export function validateFsqAcquisitionBounds(input: {
  countries: readonly string[];
  categories: readonly string[];
  maxRowsPerScope?: number;
}): { ok: true; plan: FsqPortalAcquirePlan } | { ok: false; blocks: string[] } {
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

export function normalizeFsqPortalPlaceRecord(
  record: FsqPortalPlaceRecord,
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

export function serializeNormalizedFsqPortalRecords(
  records: readonly Record<string, unknown>[]
): string {
  const lines = records.map((record) => JSON.stringify(record));
  return lines.length > 0 ? `${lines.join("\n")}\n` : "";
}

export function escapeSqlLiteral(value: string): string {
  return value.replaceAll("'", "''");
}

export function buildFsqPortalIcebergSetupSql(input: {
  portalAccessToken: string;
  endpoint?: string;
  catalogAlias?: string;
}): { createSecretSql: string; attachSql: string; loadExtensionsSql: string[] } {
  const endpoint = input.endpoint ?? FSQ_OS_PLACES_PORTAL_ICEBERG_ENDPOINT;
  const catalogAlias = input.catalogAlias ?? FSQ_OS_PLACES_PORTAL_ICEBERG_CATALOG_ALIAS;
  const tokenLiteral = escapeSqlLiteral(input.portalAccessToken);
  const endpointLiteral = escapeSqlLiteral(endpoint);
  return {
    loadExtensionsSql: ["INSTALL iceberg;", "INSTALL httpfs;", "LOAD iceberg;", "LOAD httpfs;"],
    createSecretSql: `CREATE OR REPLACE SECRET fsq_os_places_portal (TYPE ICEBERG, TOKEN '${tokenLiteral}');`,
    attachSql: `ATTACH '${escapeSqlLiteral(catalogAlias)}' AS ${catalogAlias} (TYPE ICEBERG, SECRET fsq_os_places_portal, ENDPOINT '${endpointLiteral}');`
  };
}

export function buildFsqPortalIcebergSelectSql(input: {
  table?: string;
  countryIso: string;
  limit: number;
}): { sql: string; params: { countryIso: string; limit: number } } {
  const table = input.table ?? FSQ_OS_PLACES_PORTAL_ICEBERG_TABLE;
  // Fixed identifiers only; country + limit are bound by the runner.
  return {
    sql: `
SELECT
  fsq_place_id,
  name,
  latitude,
  longitude,
  country,
  locality,
  fsq_category_ids,
  fsq_category_labels
FROM ${table}
WHERE country = $countryIso
ORDER BY fsq_place_id ASC
LIMIT $limit
`.trim(),
    params: {
      countryIso: input.countryIso,
      limit: input.limit
    }
  };
}

export async function acquireFsqOsPlacesPortalIceberg(input: {
  countries: readonly string[];
  categories: readonly string[];
  maxRowsPerScope?: number;
  preview?: boolean;
  portalAccessToken?: string;
  portalAccessTokenExpiresAt?: string;
  sourceTaxonomy?: FsqSourceTaxonomyMapping;
  endpoint?: string;
  table?: string;
  queryTimeoutMs?: number;
  now?: string;
  duckDbRunner?: FsqPortalIcebergDuckDbRunner;
  fixtureRecords?: readonly FsqPortalPlaceRecord[];
}): Promise<FsqPortalAcquireResult> {
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

  const portalAccessToken = input.portalAccessToken?.trim();
  if (!portalAccessToken && !input.fixtureRecords) {
    return { ok: false, blocks: ["portal_access_token_missing"] };
  }
  if (!input.fixtureRecords) {
    const expiry = validateFsqPortalAccessTokenExpiry({
      expiresAt: input.portalAccessTokenExpiresAt,
      now: input.now
    });
    if (!expiry.ok) {
      return { ok: false, blocks: [expiry.block] };
    }
  }

  const allowedCategories = new Set(bounds.plan.categories);
  const records: FsqPortalPlaceRecord[] = [];

  if (input.fixtureRecords) {
    const classifiedFixtures: FsqPortalPlaceRecord[] = [];
    for (const record of input.fixtureRecords) {
      if (input.sourceTaxonomy) {
        const classified = classifyProviderRecord(record, input.sourceTaxonomy);
        if (!classified.ok) {
          return { ok: false, blocks: [classified.block] };
        }
        if (allowedCategories.has(classified.record.category)) {
          classifiedFixtures.push(classified.record);
        }
      } else if (allowedCategories.has(record.category)) {
        classifiedFixtures.push(record);
      }
    }
    records.push(...filterFixtureRecords(classifiedFixtures, bounds.plan));
  } else {
    if (!input.sourceTaxonomy) {
      return { ok: false, blocks: ["source_mapping_requires_plan_refresh"] };
    }
    if (!input.duckDbRunner) {
      return { ok: false, blocks: ["portal_duckdb_runner_missing"] };
    }
    const runner = input.duckDbRunner;
    const timeoutMs = input.queryTimeoutMs ?? FSQ_OS_PLACES_PORTAL_DEFAULT_QUERY_TIMEOUT_MS;
    const perCountryLimit = Math.min(
      bounds.plan.maxRowsPerScope * bounds.plan.categories.length * 4,
      FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE * 40
    );

    for (const country of bounds.plan.countries) {
      const countryIso = FSQ_OS_PLACES_COUNTRY_ISO[country];
      if (!countryIso) {
        return { ok: false, blocks: [`country_iso_unmapped:${country}`] };
      }

      const queried = await runner.queryCountryPlaces({
        portalAccessToken: portalAccessToken!,
        endpoint: input.endpoint ?? FSQ_OS_PLACES_PORTAL_ICEBERG_ENDPOINT,
        table: input.table ?? FSQ_OS_PLACES_PORTAL_ICEBERG_TABLE,
        countryIso,
        limit: perCountryLimit,
        timeoutMs
      });
      if (!queried.ok) {
        return { ok: false, blocks: [queried.block] };
      }

      const perScope = new Map<string, number>();
      for (const row of queried.rows) {
        const classification = classifyFsqPlaceConsumerCategory({
          mapping: input.sourceTaxonomy,
          providerCategoryIds: row.providerCategoryIds,
          providerCategoryLabels: row.providerCategoryLabels
        });
        if (!classification.ok) {
          return { ok: false, blocks: [classification.block] };
        }
        if (!allowedCategories.has(classification.consumerCategory)) {
          continue;
        }
        const scopeKey = `${country}:${classification.consumerCategory}`;
        const count = perScope.get(scopeKey) ?? 0;
        if (count >= bounds.plan.maxRowsPerScope) {
          continue;
        }
        perScope.set(scopeKey, count + 1);
        records.push({
          fsqPlaceId: row.fsqPlaceId,
          name: row.name,
          latitude: row.latitude,
          longitude: row.longitude,
          geography: buildGeography(row.locality, country),
          category: classification.consumerCategory,
          providerCategoryIds: row.providerCategoryIds,
          providerCategoryLabels: row.providerCategoryLabels
        });
      }
    }
  }

  const capped = capRecordsPerScope(records, bounds.plan);
  const normalized = [...capped]
    .sort((left, right) => left.fsqPlaceId.localeCompare(right.fsqPlaceId))
    .map((record) => normalizeFsqPortalPlaceRecord(record));
  const normalizedJsonl = serializeNormalizedFsqPortalRecords(normalized);

  return {
    ok: true,
    preview: false,
    plan: bounds.plan,
    normalizedJsonl,
    providerRecordCount: capped.length
  };
}

function classifyProviderRecord(
  record: FsqPortalPlaceRecord,
  mapping: FsqSourceTaxonomyMapping
): { ok: true; record: FsqPortalPlaceRecord } | { ok: false; block: string } {
  if (
    (!record.providerCategoryIds || record.providerCategoryIds.length === 0) &&
    (!record.providerCategoryLabels || record.providerCategoryLabels.length === 0)
  ) {
    // Fixture rows may already carry consumer categories.
    return { ok: true, record };
  }

  const classification = classifyFsqPlaceConsumerCategory({
    mapping,
    providerCategoryIds: record.providerCategoryIds,
    providerCategoryLabels: record.providerCategoryLabels
  });
  if (!classification.ok) {
    return classification;
  }
  return {
    ok: true,
    record: {
      ...record,
      category: classification.consumerCategory
    }
  };
}

function filterFixtureRecords(
  fixtureRecords: readonly FsqPortalPlaceRecord[],
  plan: FsqPortalAcquirePlan
): FsqPortalPlaceRecord[] {
  const perScope = new Map<string, number>();
  const selected: FsqPortalPlaceRecord[] = [];
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

function capRecordsPerScope(
  records: readonly FsqPortalPlaceRecord[],
  plan: FsqPortalAcquirePlan
): FsqPortalPlaceRecord[] {
  const perScope = new Map<string, number>();
  const selected: FsqPortalPlaceRecord[] = [];
  const sorted = [...records].sort((left, right) =>
    `${left.geography}:${left.category}:${left.fsqPlaceId}`.localeCompare(
      `${right.geography}:${right.category}:${right.fsqPlaceId}`
    )
  );
  for (const record of sorted) {
    const country = inferCountryKey(record.geography, plan.countries);
    if (!country || !plan.categories.includes(record.category)) {
      continue;
    }
    const scopeKey = `${country}:${record.category}`;
    const count = perScope.get(scopeKey) ?? 0;
    if (count >= plan.maxRowsPerScope) {
      continue;
    }
    perScope.set(scopeKey, count + 1);
    selected.push(record);
  }
  return selected;
}

function geographyMatchesScope(
  record: FsqPortalPlaceRecord,
  scope: { country: string; category: string }
): boolean {
  if (record.category !== scope.category) {
    return false;
  }
  const geography = record.geography.toLowerCase();
  return geography === scope.country || geography.endsWith(`-${scope.country}`);
}

function inferCountryKey(geography: string, countries: readonly string[]): string | undefined {
  const lower = geography.toLowerCase();
  for (const country of countries) {
    if (lower === country || lower.endsWith(`-${country}`)) {
      return country;
    }
  }
  return undefined;
}

function buildGeography(locality: string | undefined, countryKey: string): string {
  if (!locality?.trim()) {
    return countryKey;
  }
  const slug = locality
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug ? `${slug}-${countryKey}` : countryKey;
}
