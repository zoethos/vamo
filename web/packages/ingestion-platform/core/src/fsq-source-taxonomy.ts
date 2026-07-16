/**
 * Pure FSQ → Vamo source taxonomy mapping (IP-18.8.16).
 *
 * Declarative plan contract only — no React switches, no generic orchestration
 * category policy. Classifies provider category IDs/labels into consumer
 * categories with explicit precedence and one fallback.
 */

export const FSQ_SOURCE_TAXONOMY_PROVIDER = "fsq_os_places" as const;

export interface FsqSourceTaxonomyMappingRule {
  /** Provider category IDs that match this rule (any match). */
  providerCategoryIds: string[];
  /**
   * Provider category labels that match this rule (case-insensitive).
   *
   * Foursquare can return a hierarchical label such as
   * "Dining and Drinking > Restaurant". A configured label matches either the
   * whole provider label or one exact hierarchy segment; arbitrary substrings
   * never match.
   */
  providerCategoryLabels: string[];
  /** Vamo / consumer category key. */
  consumerCategory: string;
  /** Higher wins. Ties across different consumer categories are ambiguous. */
  precedence: number;
}

export interface FsqSourceTaxonomyMapping {
  provider: typeof FSQ_SOURCE_TAXONOMY_PROVIDER;
  fallbackConsumerCategory: string;
  mappings: FsqSourceTaxonomyMappingRule[];
}

export type FsqSourceTaxonomyParseResult =
  | { ok: true; mapping: FsqSourceTaxonomyMapping }
  | { ok: false; blocks: string[] };

export type FsqClassifyPlaceCategoryResult =
  | { ok: true; consumerCategory: string; matchedBy: "mapping" | "fallback" }
  | { ok: false; block: string };

export function parseFsqSourceTaxonomy(input: unknown): FsqSourceTaxonomyParseResult {
  if (input === undefined || input === null) {
    return { ok: false, blocks: ["source_taxonomy_missing"] };
  }
  if (!isRecord(input)) {
    return { ok: false, blocks: ["source_taxonomy_invalid_shape"] };
  }

  const blocks: string[] = [];
  const provider = readString(input.provider);
  if (provider !== FSQ_SOURCE_TAXONOMY_PROVIDER) {
    blocks.push("source_taxonomy_provider_unsupported");
  }

  const fallbackConsumerCategory = readSlug(input.fallbackConsumerCategory);
  if (!fallbackConsumerCategory) {
    blocks.push("source_taxonomy_fallback_required");
  }

  const mappingsRaw = input.mappings;
  if (!Array.isArray(mappingsRaw) || mappingsRaw.length === 0) {
    blocks.push("source_taxonomy_mappings_required");
  }

  const mappings: FsqSourceTaxonomyMappingRule[] = [];
  if (Array.isArray(mappingsRaw)) {
    mappingsRaw.forEach((entry, index) => {
      if (!isRecord(entry)) {
        blocks.push(`source_taxonomy_mapping_invalid:${index}`);
        return;
      }
      const consumerCategory = readSlug(entry.consumerCategory);
      const precedence = readInteger(entry.precedence);
      const providerCategoryIds = readStringList(entry.providerCategoryIds);
      const providerCategoryLabels = readStringList(entry.providerCategoryLabels).map((label) =>
        label.toLowerCase()
      );

      if (!consumerCategory) {
        blocks.push(`source_taxonomy_mapping_consumer_required:${index}`);
      }
      if (precedence === null) {
        blocks.push(`source_taxonomy_mapping_precedence_required:${index}`);
      }
      if (providerCategoryIds.length === 0 && providerCategoryLabels.length === 0) {
        blocks.push(`source_taxonomy_mapping_match_required:${index}`);
      }
      if (!consumerCategory || precedence === null) {
        return;
      }
      mappings.push({
        providerCategoryIds,
        providerCategoryLabels,
        consumerCategory,
        precedence
      });
    });
  }

  if (blocks.length > 0 || !fallbackConsumerCategory) {
    return { ok: false, blocks };
  }

  return {
    ok: true,
    mapping: {
      provider: FSQ_SOURCE_TAXONOMY_PROVIDER,
      fallbackConsumerCategory,
      mappings
    }
  };
}

/**
 * Extract and validate sourceTaxonomy from a batch plan document/spec record.
 * Fail closed when absent — callers must not invent a mapping.
 */
export function extractFsqSourceTaxonomyFromPlan(
  planDocument: unknown
): FsqSourceTaxonomyParseResult {
  if (!isRecord(planDocument)) {
    return { ok: false, blocks: ["source_taxonomy_missing"] };
  }
  if (!("sourceTaxonomy" in planDocument) || planDocument.sourceTaxonomy === undefined) {
    return { ok: false, blocks: ["source_mapping_requires_plan_refresh"] };
  }
  const parsed = parseFsqSourceTaxonomy(planDocument.sourceTaxonomy);
  if (!parsed.ok && parsed.blocks.includes("source_taxonomy_missing")) {
    return { ok: false, blocks: ["source_mapping_requires_plan_refresh"] };
  }
  return parsed;
}

export function classifyFsqPlaceConsumerCategory(input: {
  mapping: FsqSourceTaxonomyMapping;
  providerCategoryIds?: readonly string[];
  providerCategoryLabels?: readonly string[];
}): FsqClassifyPlaceCategoryResult {
  const ids = new Set(
    (input.providerCategoryIds ?? [])
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0)
  );
  const labels = new Set(
    (input.providerCategoryLabels ?? [])
      .map((entry) => entry.trim().toLowerCase())
      .filter((entry) => entry.length > 0)
  );

  const matches: FsqSourceTaxonomyMappingRule[] = [];
  for (const rule of input.mapping.mappings) {
    const idHit = rule.providerCategoryIds.some((id) => ids.has(id));
    const labelHit = rule.providerCategoryLabels.some((label) =>
      [...labels].some((providerLabel) => providerLabelMatchesRule(providerLabel, label))
    );
    if (idHit || labelHit) {
      matches.push(rule);
    }
  }

  if (matches.length === 0) {
    return {
      ok: true,
      consumerCategory: input.mapping.fallbackConsumerCategory,
      matchedBy: "fallback"
    };
  }

  const maxPrecedence = Math.max(...matches.map((rule) => rule.precedence));
  const top = matches.filter((rule) => rule.precedence === maxPrecedence);
  const consumerCategories = [...new Set(top.map((rule) => rule.consumerCategory))].sort();
  if (consumerCategories.length !== 1) {
    return {
      ok: false,
      block: `source_category_mapping_ambiguous:${consumerCategories.join(",")}`
    };
  }

  return { ok: true, consumerCategory: consumerCategories[0]!, matchedBy: "mapping" };
}

function providerLabelMatchesRule(providerLabel: string, configuredLabel: string): boolean {
  const normalizedConfiguredLabel = configuredLabel.trim().toLowerCase();
  if (providerLabel === normalizedConfiguredLabel) {
    return true;
  }
  return providerLabel
    .split(">")
    .map((segment) => segment.trim())
    .some((segment) => segment === normalizedConfiguredLabel);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function readSlug(value: unknown): string | undefined {
  const raw = readString(value);
  return raw ? raw.toLowerCase() : undefined;
}

function readInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function readStringList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((entry): entry is string => typeof entry === "string" && entry.trim().length > 0)
    .map((entry) => entry.trim());
}
