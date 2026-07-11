/**
 * Batch target planning spec — consumer-neutral, pure parse/validate.
 *
 * IP-18 expands a declared geography/category matrix into deterministic dry-run
 * target units. Environment is explicit metadata (`targetEnvironment`); it is
 * never inferred from `targetKey`.
 */

import { parse } from "yaml";

import { findLocalSnapshotConnectionViolations } from "../../spec/src/source-connection-policy.js";
import type { SafetyMode } from "./schedule-proposal.js";
import { isLegacyTargetKey } from "./target-identity.js";

export const BATCH_PLAN_KIND = "ingestion.batch_plan" as const;

export const BATCH_FORBIDDEN_SAFETY_MODES: readonly SafetyMode[] = [
  "staging_write",
  "production_write"
];

export const BATCH_ALLOWED_SAFETY_MODES: readonly SafetyMode[] = ["dry_run"];

export type BatchTargetEnvironment = "staging" | "production";

export interface BatchGeographyRef {
  key: string;
  label?: string;
  country?: string;
}

export interface BatchBoundingBoxRef {
  key: string;
  label?: string;
  /** west,south,east,north */
  bounds: string;
  country?: string;
}

export interface BatchGeographiesSpec {
  countries?: BatchGeographyRef[];
  regions?: BatchGeographyRef[];
  cities?: BatchGeographyRef[];
  areas?: BatchGeographyRef[];
  boundingBoxes?: BatchBoundingBoxRef[];
}

export interface BatchPriorityHint {
  geography?: string;
  category?: string;
  weight: number;
}

export interface BatchBoundsSpec {
  maxUnits?: number;
  sampleRowLimitPerUnit?: number;
  defaultBatchSize?: number;
}

export interface BatchCategoryVolumeProjection {
  sourceCandidatesPerUnit?: number;
  expectedTargetWritesPerUnit?: number;
}

export interface BatchVolumeProjectionSpec {
  consumerContractRef?: string;
  defaultSourceCandidatesPerUnit?: number;
  defaultExpectedTargetWritesPerUnit?: number;
  byCategory?: Record<string, BatchCategoryVolumeProjection>;
}

export interface BatchSourceSpec {
  adapter?: string;
  connection?: Record<string, unknown>;
}

export interface BatchDryRunProposalFactsSpec {
  consumerValue?: {
    useCase?: string;
    reducesLiveCalls?: boolean;
  };
  sourceRights?: {
    canStoreFacts?: boolean;
    attributionPresent?: boolean;
    retentionDeclared?: boolean;
    liveOnly?: boolean;
  };
  targetReadiness?: {
    schemaCompatible?: boolean;
    upsertKeysDeclared?: boolean;
    rlsPostureOk?: boolean;
    stagingEnvironmentExists?: boolean;
  };
  dataQuality?: {
    requiredFieldsPresent?: boolean;
    coordinatesValid?: boolean;
  };
  checkpointability?: {
    cursorStrategyDeclared?: boolean;
    resumeTested?: boolean;
  };
  costAndQuota?: {
    rowLimitDeclared?: boolean;
    stopConditionsDeclared?: boolean;
    withinBudget?: boolean;
  };
  collision?: {
    policy?: "auto" | "review" | "block" | "none";
  };
  blastRadius?: {
    bounded?: boolean;
    firstShipmentStagingOnly?: boolean;
  };
  observability?: {
    eventsAvailable?: boolean;
    checkpointsAvailable?: boolean;
    deadLettersAvailable?: boolean;
    statsAvailable?: boolean;
  };
}

export interface BatchPlanSpec {
  kind: typeof BATCH_PLAN_KIND;
  version: number;
  id: string;
  projectKey: string;
  sourceKey: string;
  targetProfileKey: string;
  /** Environment-neutral consumer target key. */
  targetKey: string;
  /** Explicit delivery environment — never encoded in targetKey. */
  targetEnvironment: BatchTargetEnvironment;
  safetyMode: SafetyMode;
  geographies: BatchGeographiesSpec;
  categories: string[];
  priorityHints?: BatchPriorityHint[];
  bounds?: BatchBoundsSpec;
  consumerContractRef?: string;
  source?: BatchSourceSpec;
  volumeProjection?: BatchVolumeProjectionSpec;
  dryRunProposalFacts?: BatchDryRunProposalFactsSpec;
  notes?: string;
}

export type BatchPlanSpecErrorCode =
  | "invalid_yaml"
  | "invalid_shape"
  | "missing_required"
  | "unsafe_safety_mode"
  | "unsafe_source_connection"
  | "legacy_target_key"
  | "empty_scope";

export interface BatchPlanSpecError {
  code: BatchPlanSpecErrorCode;
  path: string;
  message: string;
}

export type ParseBatchPlanSpecResult =
  | { ok: true; spec: BatchPlanSpec; errors: [] }
  | { ok: false; errors: BatchPlanSpecError[] };

export function parseBatchPlanSpec(input: string | unknown): ParseBatchPlanSpecResult {
  const document = typeof input === "string" ? parseYaml(input) : input;
  if (document && typeof document === "object" && "errors" in (document as object)) {
    return document as { ok: false; errors: BatchPlanSpecError[] };
  }

  const errors: BatchPlanSpecError[] = [];
  if (!isRecord(document)) {
    return fail([{ code: "invalid_shape", path: "$", message: "Batch plan must be an object." }]);
  }

  const kind = readString(document, "kind");
  if (kind !== BATCH_PLAN_KIND) {
    errors.push({
      code: "invalid_shape",
      path: "kind",
      message: `Expected "${BATCH_PLAN_KIND}".`
    });
  }

  const safetyMode = (readString(document, "safetyMode") ?? "dry_run") as SafetyMode;
  if (!BATCH_ALLOWED_SAFETY_MODES.includes(safetyMode)) {
    errors.push({
      code: "unsafe_safety_mode",
      path: "safetyMode",
      message: `Batch planning slice allows only dry_run, not "${safetyMode}".`
    });
  }
  if (BATCH_FORBIDDEN_SAFETY_MODES.includes(safetyMode)) {
    errors.push({
      code: "unsafe_safety_mode",
      path: "safetyMode",
      message: `Unsafe safety mode "${safetyMode}" is forbidden in IP-18 planning.`
    });
  }

  const targetKey = readString(document, "targetKey");
  if (!targetKey) {
    errors.push({ code: "missing_required", path: "targetKey", message: "targetKey is required." });
  } else if (isLegacyTargetKey(targetKey) || targetKey.endsWith("-staging") || targetKey.endsWith("-production")) {
    errors.push({
      code: "legacy_target_key",
      path: "targetKey",
      message: "targetKey must be environment-neutral; do not encode staging/production in the key."
    });
  }

  const targetEnvironment = readString(document, "targetEnvironment") as BatchTargetEnvironment | undefined;
  if (targetEnvironment !== "staging" && targetEnvironment !== "production") {
    errors.push({
      code: "missing_required",
      path: "targetEnvironment",
      message: 'targetEnvironment must be explicit: "staging" or "production".'
    });
  }

  const projectKey = readString(document, "projectKey");
  if (!projectKey) {
    errors.push({ code: "missing_required", path: "projectKey", message: "projectKey is required." });
  }
  const sourceKey = readString(document, "sourceKey");
  if (!sourceKey) {
    errors.push({ code: "missing_required", path: "sourceKey", message: "sourceKey is required." });
  } else {
    validateSourceKeySafety(sourceKey, errors);
  }
  validateSourceBlock(document.source, errors);
  const targetProfileKey = readString(document, "targetProfileKey");
  if (!targetProfileKey) {
    errors.push({
      code: "missing_required",
      path: "targetProfileKey",
      message: "targetProfileKey is required."
    });
  }

  const geographies = parseGeographies(document.geographies, errors);
  const categories = parseCategories(document.categories, errors);
  if (categories.length === 0) {
    errors.push({
      code: "empty_scope",
      path: "categories",
      message: "At least one category is required."
    });
  }
  if (!hasAnyGeography(geographies)) {
    errors.push({
      code: "empty_scope",
      path: "geographies",
      message: "Declare at least one country, region, city, area, or bounding box."
    });
  }

  const id = readString(document, "id");
  if (!id) {
    errors.push({ code: "missing_required", path: "id", message: "id is required." });
  }

  const priorityHints = parsePriorityHints(document.priorityHints, errors);
  const source = parseSource(document.source, errors);
  const volumeProjection = parseVolumeProjection(document.volumeProjection, errors);
  const dryRunProposalFacts = parseDryRunProposalFacts(document.dryRunProposalFacts, errors);

  if (errors.length > 0) {
    return fail(errors);
  }

  return {
    ok: true,
    errors: [],
    spec: {
      kind: BATCH_PLAN_KIND,
      version: readNumber(document, "version") ?? 1,
      id: id!,
      projectKey: projectKey!,
      sourceKey: sourceKey!,
      targetProfileKey: targetProfileKey!,
      targetKey: targetKey!,
      targetEnvironment: targetEnvironment!,
      safetyMode,
      geographies,
      categories,
      priorityHints,
      bounds: parseBounds(document.bounds),
      consumerContractRef: readString(document, "consumerContractRef"),
      source,
      volumeProjection,
      dryRunProposalFacts,
      notes: readString(document, "notes")
    }
  };
}

function parseGeographies(value: unknown, errors: BatchPlanSpecError[]): BatchGeographiesSpec {
  if (!isRecord(value)) {
    errors.push({
      code: "missing_required",
      path: "geographies",
      message: "geographies object is required."
    });
    return {};
  }
  return {
    countries: parseGeoList(value.countries, "geographies.countries", errors),
    regions: parseGeoList(value.regions, "geographies.regions", errors),
    cities: parseGeoList(value.cities, "geographies.cities", errors),
    areas: parseGeoList(value.areas, "geographies.areas", errors),
    boundingBoxes: parseBoundingBoxes(value.boundingBoxes, errors)
  };
}

function parseGeoList(
  value: unknown,
  path: string,
  errors: BatchPlanSpecError[]
): BatchGeographyRef[] | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!Array.isArray(value)) {
    errors.push({ code: "invalid_shape", path, message: "Expected an array." });
    return undefined;
  }
  const items: BatchGeographyRef[] = [];
  value.forEach((entry, index) => {
    if (!isRecord(entry)) {
      errors.push({ code: "invalid_shape", path: `${path}[${index}]`, message: "Expected an object." });
      return;
    }
    const key = readString(entry, "key");
    if (!key) {
      errors.push({
        code: "missing_required",
        path: `${path}[${index}].key`,
        message: "geography key is required."
      });
      return;
    }
    items.push({
      key: normalizeSlug(key),
      label: readString(entry, "label"),
      country: entry.country ? normalizeSlug(String(entry.country)) : undefined
    });
  });
  return items;
}

function parseBoundingBoxes(value: unknown, errors: BatchPlanSpecError[]): BatchBoundingBoxRef[] | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!Array.isArray(value)) {
    errors.push({
      code: "invalid_shape",
      path: "geographies.boundingBoxes",
      message: "Expected an array."
    });
    return undefined;
  }
  const items: BatchBoundingBoxRef[] = [];
  value.forEach((entry, index) => {
    if (!isRecord(entry)) {
      errors.push({
        code: "invalid_shape",
        path: `geographies.boundingBoxes[${index}]`,
        message: "Expected an object."
      });
      return;
    }
    const key = readString(entry, "key");
    const bounds = readString(entry, "bounds");
    if (!key || !bounds) {
      errors.push({
        code: "missing_required",
        path: `geographies.boundingBoxes[${index}]`,
        message: "bounding box key and bounds are required."
      });
      return;
    }
    items.push({
      key: normalizeSlug(key),
      bounds: bounds.trim(),
      label: readString(entry, "label"),
      country: entry.country ? normalizeSlug(String(entry.country)) : undefined
    });
  });
  return items;
}

function parseCategories(value: unknown, errors: BatchPlanSpecError[]): string[] {
  if (!Array.isArray(value)) {
    errors.push({ code: "missing_required", path: "categories", message: "categories array is required." });
    return [];
  }
  const categories = value
    .map((entry, index) => {
      if (typeof entry !== "string" || entry.trim().length === 0) {
        errors.push({
          code: "invalid_shape",
          path: `categories[${index}]`,
          message: "category must be a non-empty string."
        });
        return null;
      }
      return normalizeSlug(entry);
    })
    .filter((entry): entry is string => entry !== null);
  return [...new Set(categories)].sort();
}

function parsePriorityHints(value: unknown, errors: BatchPlanSpecError[]): BatchPriorityHint[] | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!Array.isArray(value)) {
    errors.push({ code: "invalid_shape", path: "priorityHints", message: "Expected an array." });
    return undefined;
  }
  const hints: BatchPriorityHint[] = [];
  value.forEach((entry, index) => {
    if (!isRecord(entry)) {
      errors.push({
        code: "invalid_shape",
        path: `priorityHints[${index}]`,
        message: "Expected an object."
      });
      return;
    }
    const weight = readNumber(entry, "weight");
    if (weight === undefined) {
      errors.push({
        code: "missing_required",
        path: `priorityHints[${index}].weight`,
        message: "weight is required."
      });
      return;
    }
    hints.push({
      geography: entry.geography ? normalizeSlug(String(entry.geography)) : undefined,
      category: entry.category ? normalizeSlug(String(entry.category)) : undefined,
      weight
    });
  });
  return hints;
}

function parseBounds(value: unknown): BatchBoundsSpec | undefined {
  if (!isRecord(value)) {
    return undefined;
  }
  return {
    maxUnits: readNumber(value, "maxUnits"),
    sampleRowLimitPerUnit: readNumber(value, "sampleRowLimitPerUnit"),
    defaultBatchSize: readNumber(value, "defaultBatchSize")
  };
}

function parseSource(value: unknown, errors: BatchPlanSpecError[]): BatchSourceSpec | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    errors.push({ code: "invalid_shape", path: "source", message: "Expected an object." });
    return undefined;
  }
  const adapter = readString(value, "adapter");
  if (adapter && adapter !== "snapshot") {
    errors.push({
      code: "unsafe_source_connection",
      path: "source.adapter",
      message: `Batch planning allows only snapshot adapter, not "${adapter}".`
    });
  }
  if (value.connection !== undefined && !isRecord(value.connection)) {
    errors.push({
      code: "invalid_shape",
      path: "source.connection",
      message: "Expected an object."
    });
  }
  const connection = isRecord(value.connection) ? value.connection : undefined;
  return { adapter, connection };
}

function parseDryRunProposalFacts(
  value: unknown,
  errors: BatchPlanSpecError[]
): BatchDryRunProposalFactsSpec | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    errors.push({
      code: "invalid_shape",
      path: "dryRunProposalFacts",
      message: "Expected an object."
    });
    return undefined;
  }
  return {
    consumerValue: parseConsumerValueFacts(value.consumerValue, errors),
    sourceRights: parseBooleanFacts(
      value.sourceRights,
      "dryRunProposalFacts.sourceRights",
      ["canStoreFacts", "attributionPresent", "retentionDeclared", "liveOnly"],
      errors
    ),
    targetReadiness: parseBooleanFacts(
      value.targetReadiness,
      "dryRunProposalFacts.targetReadiness",
      ["schemaCompatible", "upsertKeysDeclared", "rlsPostureOk", "stagingEnvironmentExists"],
      errors
    ),
    dataQuality: parseBooleanFacts(
      value.dataQuality,
      "dryRunProposalFacts.dataQuality",
      ["requiredFieldsPresent", "coordinatesValid"],
      errors
    ),
    checkpointability: parseBooleanFacts(
      value.checkpointability,
      "dryRunProposalFacts.checkpointability",
      ["cursorStrategyDeclared", "resumeTested"],
      errors
    ),
    costAndQuota: parseBooleanFacts(
      value.costAndQuota,
      "dryRunProposalFacts.costAndQuota",
      ["rowLimitDeclared", "stopConditionsDeclared", "withinBudget"],
      errors
    ),
    collision: parseCollisionFacts(value.collision, errors),
    blastRadius: parseBooleanFacts(
      value.blastRadius,
      "dryRunProposalFacts.blastRadius",
      ["bounded", "firstShipmentStagingOnly"],
      errors
    ),
    observability: parseBooleanFacts(
      value.observability,
      "dryRunProposalFacts.observability",
      ["eventsAvailable", "checkpointsAvailable", "deadLettersAvailable", "statsAvailable"],
      errors
    )
  };
}

function parseConsumerValueFacts(
  value: unknown,
  errors: BatchPlanSpecError[]
): BatchDryRunProposalFactsSpec["consumerValue"] {
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    errors.push({
      code: "invalid_shape",
      path: "dryRunProposalFacts.consumerValue",
      message: "Expected an object."
    });
    return undefined;
  }
  return {
    useCase: readString(value, "useCase"),
    reducesLiveCalls: readOptionalBoolean(
      value,
      "reducesLiveCalls",
      "dryRunProposalFacts.consumerValue.reducesLiveCalls",
      errors
    )
  };
}

function parseBooleanFacts<K extends string>(
  value: unknown,
  path: string,
  keys: readonly K[],
  errors: BatchPlanSpecError[]
): Partial<Record<K, boolean>> | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    errors.push({ code: "invalid_shape", path, message: "Expected an object." });
    return undefined;
  }
  const parsed: Partial<Record<K, boolean>> = {};
  for (const key of keys) {
    const booleanValue = readOptionalBoolean(value, key, `${path}.${key}`, errors);
    if (booleanValue !== undefined) {
      parsed[key] = booleanValue;
    }
  }
  return parsed;
}

function parseCollisionFacts(
  value: unknown,
  errors: BatchPlanSpecError[]
): BatchDryRunProposalFactsSpec["collision"] {
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    errors.push({
      code: "invalid_shape",
      path: "dryRunProposalFacts.collision",
      message: "Expected an object."
    });
    return undefined;
  }
  const policy = readString(value, "policy");
  if (policy === undefined) {
    return {};
  }
  if (policy !== "auto" && policy !== "review" && policy !== "block" && policy !== "none") {
    errors.push({
      code: "invalid_shape",
      path: "dryRunProposalFacts.collision.policy",
      message: 'collision.policy must be "auto", "review", "block", or "none".'
    });
    return {};
  }
  return { policy };
}

function parseVolumeProjection(
  value: unknown,
  errors: BatchPlanSpecError[]
): BatchVolumeProjectionSpec | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    errors.push({
      code: "invalid_shape",
      path: "volumeProjection",
      message: "Expected an object."
    });
    return undefined;
  }
  const byCategory: Record<string, BatchCategoryVolumeProjection> = {};
  if (value.byCategory !== undefined) {
    if (!isRecord(value.byCategory)) {
      errors.push({
        code: "invalid_shape",
        path: "volumeProjection.byCategory",
        message: "Expected an object."
      });
    } else {
      for (const [rawKey, entry] of Object.entries(value.byCategory)) {
        const key = normalizeSlug(rawKey);
        if (!isRecord(entry)) {
          errors.push({
            code: "invalid_shape",
            path: `volumeProjection.byCategory.${rawKey}`,
            message: "Expected an object."
          });
          continue;
        }
        byCategory[key] = {
          sourceCandidatesPerUnit: readNumber(entry, "sourceCandidatesPerUnit"),
          expectedTargetWritesPerUnit: readNumber(entry, "expectedTargetWritesPerUnit")
        };
      }
    }
  }
  return {
    consumerContractRef: readString(value, "consumerContractRef"),
    defaultSourceCandidatesPerUnit: readNumber(value, "defaultSourceCandidatesPerUnit"),
    defaultExpectedTargetWritesPerUnit: readNumber(value, "defaultExpectedTargetWritesPerUnit"),
    byCategory: Object.keys(byCategory).length > 0 ? byCategory : undefined
  };
}

function validateSourceKeySafety(sourceKey: string, errors: BatchPlanSpecError[]): void {
  if (looksLikeUrl(sourceKey)) {
    errors.push({
      code: "unsafe_source_connection",
      path: "sourceKey",
      message: "sourceKey must not be a URL; use a snapshot source key instead."
    });
  }
  if (/\blive\b/i.test(sourceKey) || /\bapi\b/i.test(sourceKey)) {
    errors.push({
      code: "unsafe_source_connection",
      path: "sourceKey",
      message: "Batch planning forbids live/API source keys in IP-18.8 planning slices."
    });
  }
}

function validateSourceBlock(value: unknown, errors: BatchPlanSpecError[]): void {
  if (!isRecord(value)) {
    return;
  }
  const connection = isRecord(value.connection) ? value.connection : undefined;
  for (const violation of findLocalSnapshotConnectionViolations(connection, {
    pathPrefix: "source.connection"
  })) {
    errors.push({
      code: "unsafe_source_connection",
      path: violation.path,
      message: violation.message
    });
  }
}

function looksLikeUrl(value: string): boolean {
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(value);
}

function hasAnyGeography(geographies: BatchGeographiesSpec): boolean {
  return Boolean(
    geographies.countries?.length ||
      geographies.regions?.length ||
      geographies.cities?.length ||
      geographies.areas?.length ||
      geographies.boundingBoxes?.length
  );
}

function parseYaml(input: string): unknown | { ok: false; errors: BatchPlanSpecError[] } {
  try {
    return parse(input);
  } catch (error) {
    return fail([
      {
        code: "invalid_yaml",
        path: "$",
        message: error instanceof Error ? error.message : "YAML could not be parsed."
      }
    ]);
  }
}

function fail(errors: BatchPlanSpecError[]): ParseBatchPlanSpecResult {
  return { ok: false, errors };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readString(record: Record<string, unknown>, key: string): string | undefined {
  const value = record[key];
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function readNumber(record: Record<string, unknown>, key: string): number | undefined {
  const value = record[key];
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function readOptionalBoolean(
  record: Record<string, unknown>,
  key: string,
  path: string,
  errors: BatchPlanSpecError[]
): boolean | undefined {
  const value = record[key];
  if (value === undefined) {
    return undefined;
  }
  if (typeof value === "boolean") {
    return value;
  }
  errors.push({
    code: "invalid_shape",
    path,
    message: "Expected a boolean."
  });
  return undefined;
}

function normalizeSlug(value: string): string {
  return value.trim().toLowerCase().replace(/\s+/g, "-");
}
