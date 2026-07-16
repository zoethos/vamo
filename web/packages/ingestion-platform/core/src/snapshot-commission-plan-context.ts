/**
 * Server-derived snapshot commissioning plan context (IP-18.8.13).
 */

import { parseBatchPlanSpec } from "./batch-plan-spec.js";
import {
  FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE,
  validateFsqAcquisitionBounds
} from "./fsq-acquisition-scope.js";
import {
  extractFsqSourceTaxonomyFromPlan,
  type FsqSourceTaxonomyMapping
} from "./fsq-source-taxonomy.js";
import { snapshotCommissionOperatorErrorForCode } from "./snapshot-commission-errors.js";

export const SNAPSHOT_COMMISSION_SUPPORTED_SOURCE_KEYS = ["fsq-os-places-snapshot"] as const;

export interface SnapshotCommissionPlanContext {
  projectKey: string;
  planKey: string;
  sourceKey: string;
  planStatus: string;
  allowedCountries: string[];
  allowedCategories: string[];
  maxRowsPerScopeLimit: number;
  sourceTaxonomy: FsqSourceTaxonomyMapping | null;
}

export function extractPlanCommissionBounds(specInput: Record<string, unknown>): {
  allowedCountries: string[];
  allowedCategories: string[];
  maxRowsPerScopeLimit: number;
  sourceTaxonomy: FsqSourceTaxonomyMapping | null;
} {
  const parsed = parseBatchPlanSpec(specInput);
  if (!parsed.ok) {
    return {
      allowedCountries: [],
      allowedCategories: [],
      maxRowsPerScopeLimit: FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE,
      sourceTaxonomy: null
    };
  }

  const countries = new Set<string>();
  for (const country of parsed.spec.geographies.countries ?? []) {
    if (country.key?.trim()) {
      countries.add(country.key.trim().toLowerCase());
    }
  }
  for (const region of parsed.spec.geographies.regions ?? []) {
    if (region.country?.trim()) {
      countries.add(region.country.trim().toLowerCase());
    }
  }
  for (const city of parsed.spec.geographies.cities ?? []) {
    if (city.country?.trim()) {
      countries.add(city.country.trim().toLowerCase());
    }
  }

  const categories = [...new Set(parsed.spec.categories.map((entry) => entry.trim().toLowerCase()))].sort();
  const maxRowsPerScopeLimit =
    parsed.spec.bounds?.sampleRowLimitPerUnit ?? FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE;
  const taxonomy = extractFsqSourceTaxonomyFromPlan(specInput);

  return {
    allowedCountries: [...countries].sort(),
    allowedCategories: categories,
    maxRowsPerScopeLimit,
    sourceTaxonomy: taxonomy.ok ? taxonomy.mapping : null
  };
}

export function validateSnapshotCommissionScopeAgainstPlan(input: {
  countries: readonly string[];
  categories: readonly string[];
  maxRowsPerScope: number;
  plan: SnapshotCommissionPlanContext;
}):
  | { ok: true; countries: string[]; categories: string[]; maxRowsPerScope: number }
  | { ok: false; code: string; error: string } {
  const fsqBounds = validateFsqAcquisitionBounds({
    countries: input.countries,
    categories: input.categories,
    maxRowsPerScope: input.maxRowsPerScope
  });
  if (!fsqBounds.ok) {
    return {
      ok: false,
      code: "scope_out_of_bounds",
      error: "The requested scope is outside approved FSQ bounds."
    };
  }

  const invalidCountries = fsqBounds.plan.countries.filter(
    (country) => !input.plan.allowedCountries.includes(country)
  );
  const invalidCategories = fsqBounds.plan.categories.filter(
    (category) => !input.plan.allowedCategories.includes(category)
  );
  if (invalidCountries.length > 0 || invalidCategories.length > 0) {
    return {
      ok: false,
      code: "scope_out_of_bounds",
      error: "The requested scope is outside the active batch plan contract."
    };
  }

  if (input.maxRowsPerScope > input.plan.maxRowsPerScopeLimit) {
    return {
      ok: false,
      code: "scope_out_of_bounds",
      error: "The requested max rows per scope exceeds the active batch plan limit."
    };
  }

  return {
    ok: true,
    countries: fsqBounds.plan.countries,
    categories: fsqBounds.plan.categories,
    maxRowsPerScope: fsqBounds.plan.maxRowsPerScope
  };
}

export function isSnapshotCommissionSupportedSourceKey(sourceKey: string): boolean {
  return (SNAPSHOT_COMMISSION_SUPPORTED_SOURCE_KEYS as readonly string[]).includes(sourceKey);
}

export function assertCommissionPlanHasSourceTaxonomy(
  plan: SnapshotCommissionPlanContext
): { ok: true } | { ok: false; code: string; error: string } {
  if (!plan.sourceTaxonomy) {
    return {
      ok: false,
      code: "source_mapping_requires_plan_refresh",
      error: snapshotCommissionOperatorErrorForCode("source_mapping_requires_plan_refresh")
    };
  }
  return { ok: true };
}
