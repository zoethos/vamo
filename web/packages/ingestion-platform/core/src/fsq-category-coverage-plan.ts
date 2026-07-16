/**
 * Pure FSQ category-aware coverage planning (IP-18.8.18).
 *
 * Derives per country × consumer-category Iceberg query predicates from
 * sourceTaxonomy provider IDs, and assesses requested-scope coverage from
 * valid-row matrices. Does not invent zero cells or treat fallback as query
 * coverage evidence.
 */

import type { FsqSourceTaxonomyMapping } from "./fsq-source-taxonomy.js";

export interface FsqCategoryQueryScope {
  country: string;
  countryIso: string;
  consumerCategory: string;
  providerCategoryIds: string[];
  maxRowsPerScope: number;
}

export interface FsqCategoryCoveragePlan {
  scopes: FsqCategoryQueryScope[];
}

export type BuildFsqCategoryCoveragePlanResult =
  | { ok: true; plan: FsqCategoryCoveragePlan }
  | { ok: false; blocks: string[] };

export interface FsqRequestedCoverageScope {
  country: string;
  category: string;
}

export interface FsqRequestedCoverageAssessment {
  requestedScopeCount: number;
  coveredScopeCount: number;
  missingScopes: FsqRequestedCoverageScope[];
  byCountryAndPoiType: Record<string, Record<string, number>>;
}

/**
 * Country plan keys → ISO-3166 alpha-2 used by FSQ OS Places.
 * Kept here so the pure planner can build query scopes without the adapter.
 */
export const FSQ_CATEGORY_COVERAGE_COUNTRY_ISO: Readonly<Record<string, string>> = {
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

/**
 * Collect explicit provider category IDs that map to a consumer category.
 * Labels-only mappings and the fallback category contribute nothing.
 */
export function providerCategoryIdsForConsumerCategory(
  mapping: FsqSourceTaxonomyMapping,
  consumerCategory: string
): string[] {
  const ids = new Set<string>();
  for (const rule of mapping.mappings) {
    if (rule.consumerCategory !== consumerCategory) {
      continue;
    }
    for (const id of rule.providerCategoryIds) {
      const trimmed = id.trim();
      if (trimmed.length > 0) {
        ids.add(trimmed);
      }
    }
  }
  return [...ids].sort((left, right) => left.localeCompare(right));
}

export function buildFsqCategoryCoveragePlan(input: {
  countries: readonly string[];
  categories: readonly string[];
  maxRowsPerScope: number;
  sourceTaxonomy: FsqSourceTaxonomyMapping;
  countryIsoByKey?: Readonly<Record<string, string>>;
}): BuildFsqCategoryCoveragePlanResult {
  const countryIsoByKey = input.countryIsoByKey ?? FSQ_CATEGORY_COVERAGE_COUNTRY_ISO;
  const blocks: string[] = [];
  const scopes: FsqCategoryQueryScope[] = [];

  const countries = [...new Set(input.countries.map((entry) => entry.trim().toLowerCase()))].sort();
  const categories = [...new Set(input.categories.map((entry) => entry.trim().toLowerCase()))].sort();

  for (const category of categories) {
    const providerCategoryIds = providerCategoryIdsForConsumerCategory(
      input.sourceTaxonomy,
      category
    );
    if (providerCategoryIds.length === 0) {
      blocks.push(`source_category_query_ids_required:${category}`);
    }
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  for (const country of countries) {
    const countryIso = countryIsoByKey[country];
    if (!countryIso) {
      blocks.push(`country_iso_unmapped:${country}`);
      continue;
    }
    for (const consumerCategory of categories) {
      scopes.push({
        country,
        countryIso,
        consumerCategory,
        providerCategoryIds: providerCategoryIdsForConsumerCategory(
          input.sourceTaxonomy,
          consumerCategory
        ),
        maxRowsPerScope: input.maxRowsPerScope
      });
    }
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  return {
    ok: true,
    plan: {
      scopes: scopes.sort((left, right) =>
        `${left.country}:${left.consumerCategory}`.localeCompare(
          `${right.country}:${right.consumerCategory}`
        )
      )
    }
  };
}

/**
 * Assess requested country × POI-type coverage from a valid-row matrix.
 * Missing scopes are reported for operators; this never activates or writes.
 */
export function assessFsqRequestedCoverage(input: {
  countries: readonly string[];
  categories: readonly string[];
  byCountryAndPoiType: Record<string, Record<string, number>>;
}): FsqRequestedCoverageAssessment {
  const countries = [...new Set(input.countries.map((entry) => entry.trim().toLowerCase()))].sort();
  const categories = [...new Set(input.categories.map((entry) => entry.trim().toLowerCase()))].sort();
  const missingScopes: FsqRequestedCoverageScope[] = [];
  let coveredScopeCount = 0;

  for (const country of countries) {
    for (const category of categories) {
      const count = input.byCountryAndPoiType[country]?.[category] ?? 0;
      if (count > 0) {
        coveredScopeCount += 1;
      } else {
        missingScopes.push({ country, category });
      }
    }
  }

  return {
    requestedScopeCount: countries.length * categories.length,
    coveredScopeCount,
    missingScopes,
    byCountryAndPoiType: input.byCountryAndPoiType
  };
}

export function formatFsqRequestedCoverageAssessment(
  assessment: FsqRequestedCoverageAssessment
): string[] {
  const lines = [
    `- requested scopes: ${assessment.requestedScopeCount}`,
    `- covered scopes: ${assessment.coveredScopeCount}`,
    `- missing scopes: ${assessment.missingScopes.length}`
  ];
  if (assessment.missingScopes.length > 0) {
    lines.push(
      `- missing country / POI-type scopes: ${assessment.missingScopes
        .map((scope) => `${scope.country}/${scope.category}`)
        .join(", ")}`
    );
  } else {
    lines.push("- missing country / POI-type scopes: none");
  }
  lines.push(
    `- valid-row country × POI-type coverage: ${JSON.stringify(assessment.byCountryAndPoiType)}`
  );
  return lines;
}
