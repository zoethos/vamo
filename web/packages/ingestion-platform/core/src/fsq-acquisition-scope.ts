/**
 * Pure FSQ snapshot acquisition scope bounds (IP-18.8.10 / IP-18.8.13).
 *
 * Provider-neutral scope validation shared by commissioning and acquisition.
 */

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
export const FSQ_ACQUISITION_MAX_ROWS_PER_SCOPE_LIMIT = 1000;

export interface FsqAcquisitionScopePlan {
  countries: string[];
  categories: string[];
  maxRowsPerScope: number;
}

export function validateFsqAcquisitionBounds(input: {
  countries: readonly string[];
  categories: readonly string[];
  maxRowsPerScope?: number;
}): { ok: true; plan: FsqAcquisitionScopePlan } | { ok: false; blocks: string[] } {
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
  if (
    !Number.isInteger(maxRowsPerScope) ||
    maxRowsPerScope < 1 ||
    maxRowsPerScope > FSQ_ACQUISITION_MAX_ROWS_PER_SCOPE_LIMIT
  ) {
    blocks.push("max_rows_per_scope_out_of_bounds");
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  return {
    ok: true,
    plan: {
      countries,
      categories,
      maxRowsPerScope
    }
  };
}
