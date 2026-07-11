/**
 * Full-data batch plan preview — pure read model for IP-18.8.0.
 *
 * Expands a contract-driven batch spec into queue unit counts, geography/category
 * coverage, and source-candidate vs expected target-write projections. No DB,
 * network, provider calls, or target writes.
 */

import type { BatchPlanResult, BatchPlanUnit, BatchCoverageSummary } from "./batch-planner.js";
import { buildBatchPlan, type BuildBatchPlanInput } from "./batch-planner.js";
import type { BatchPlanSpec, BatchVolumeProjectionSpec } from "./batch-plan-spec.js";
import {
  resolveConsumerDisplayFields,
  resolveDefaultBatchQueueDisplayFields,
  type ConsumerDisplayFieldSpec
} from "./consumer-display-fields.js";

export interface BatchFullDataCategoryVolume {
  unitCount: number;
  sourceCandidates: number;
  expectedTargetWrites: number;
  displayLabel?: string;
}

export interface BatchFullDataCountryVolume {
  unitCount: number;
  sourceCandidates: number;
  expectedTargetWrites: number;
}

export interface BatchFullDataVolumeSummary {
  totalSourceCandidates: number;
  totalExpectedTargetWrites: number;
  perCategory: Record<string, BatchFullDataCategoryVolume>;
  perCountry: Record<string, BatchFullDataCountryVolume>;
}

export interface BatchFullDataPlanPreview {
  planId: string;
  projectKey: string;
  targetKey: string;
  targetEnvironment: string;
  sourceKey: string;
  safetyMode: string;
  consumerContractRef?: string;
  queueUnitCount: number;
  plannedUnits: number;
  blockedUnits: number;
  coverage: BatchCoverageSummary;
  coverageMatrix: Record<string, Record<string, number>>;
  volume: BatchFullDataVolumeSummary;
  nextAction: string;
  previewUnitKeys: string[];
}

export interface BuildBatchFullDataPlanPreviewInput {
  spec: BatchPlanSpec;
  plan?: BatchPlanResult;
  candidateTemplate?: BuildBatchPlanInput["candidateTemplate"];
  previewUnitKeyLimit?: number;
  displayFields?: readonly ConsumerDisplayFieldSpec[];
}

export function buildBatchFullDataPlanPreview(
  input: BuildBatchFullDataPlanPreviewInput
): BatchFullDataPlanPreview {
  const plan = input.plan ?? buildBatchPlan({ spec: input.spec, candidateTemplate: input.candidateTemplate });
  const displayFields =
    input.displayFields ??
    resolveDefaultBatchQueueDisplayFields({
      projectKey: plan.projectKey,
      targetKey: plan.targetKey
    });
  const consumerContractRef =
    input.spec.consumerContractRef ?? input.spec.volumeProjection?.consumerContractRef;
  const volume = summarizeVolume(plan.units, input.spec, displayFields);
  const coverageMatrix = buildCoverageMatrix(plan.units);

  return {
    planId: plan.planId,
    projectKey: plan.projectKey,
    targetKey: plan.targetKey,
    targetEnvironment: plan.targetEnvironment,
    sourceKey: plan.sourceKey,
    safetyMode: plan.safetyMode,
    consumerContractRef,
    queueUnitCount: plan.totalUnits,
    plannedUnits: plan.plannedUnits,
    blockedUnits: plan.blockedUnits,
    coverage: plan.coverage,
    coverageMatrix,
    volume,
    nextAction: plan.nextAction,
    previewUnitKeys: plan.units
      .slice(0, input.previewUnitKeyLimit ?? 8)
      .map((unit) => unit.unitKey)
  };
}

function summarizeVolume(
  units: BatchPlanUnit[],
  spec: BatchPlanSpec,
  displayFields: readonly ConsumerDisplayFieldSpec[]
): BatchFullDataVolumeSummary {
  const perCategory: Record<string, BatchFullDataCategoryVolume> = {};
  const perCountry: Record<string, BatchFullDataCountryVolume> = {};
  let totalSourceCandidates = 0;
  let totalExpectedTargetWrites = 0;

  for (const unit of units) {
    if (unit.status !== "planned") {
      continue;
    }
    const projection = resolveUnitVolume(spec, unit.category);
    totalSourceCandidates += projection.sourceCandidates;
    totalExpectedTargetWrites += projection.expectedTargetWrites;

    const country = inferCountry(unit);
    const categoryEntry = perCategory[unit.category] ?? {
      unitCount: 0,
      sourceCandidates: 0,
      expectedTargetWrites: 0
    };
    categoryEntry.unitCount += 1;
    categoryEntry.sourceCandidates += projection.sourceCandidates;
    categoryEntry.expectedTargetWrites += projection.expectedTargetWrites;
    if (!categoryEntry.displayLabel) {
      categoryEntry.displayLabel = resolveCategoryDisplayLabel(displayFields, unit, spec);
    }
    perCategory[unit.category] = categoryEntry;

    const countryEntry = perCountry[country] ?? {
      unitCount: 0,
      sourceCandidates: 0,
      expectedTargetWrites: 0
    };
    countryEntry.unitCount += 1;
    countryEntry.sourceCandidates += projection.sourceCandidates;
    countryEntry.expectedTargetWrites += projection.expectedTargetWrites;
    perCountry[country] = countryEntry;
  }

  return {
    totalSourceCandidates,
    totalExpectedTargetWrites,
    perCategory,
    perCountry
  };
}

export function resolveUnitVolume(
  spec: BatchPlanSpec,
  category: string
): { sourceCandidates: number; expectedTargetWrites: number } {
  const projection = spec.volumeProjection;
  const categoryOverride = projection?.byCategory?.[category];
  const fallbackSource =
    spec.bounds?.sampleRowLimitPerUnit ??
    projection?.defaultSourceCandidatesPerUnit ??
    50;
  const sourceCandidates =
    categoryOverride?.sourceCandidatesPerUnit ??
    projection?.defaultSourceCandidatesPerUnit ??
    fallbackSource;
  const expectedTargetWrites =
    categoryOverride?.expectedTargetWritesPerUnit ??
    projection?.defaultExpectedTargetWritesPerUnit ??
    sourceCandidates;

  return { sourceCandidates, expectedTargetWrites };
}

function buildCoverageMatrix(units: BatchPlanUnit[]): Record<string, Record<string, number>> {
  const matrix: Record<string, Record<string, number>> = {};
  for (const unit of units) {
    if (unit.status !== "planned") {
      continue;
    }
    const country = inferCountry(unit);
    matrix[country] ??= {};
    matrix[country]![unit.category] = (matrix[country]![unit.category] ?? 0) + 1;
  }
  return matrix;
}

function resolveCategoryDisplayLabel(
  displayFields: readonly ConsumerDisplayFieldSpec[],
  unit: BatchPlanUnit,
  spec: BatchPlanSpec
): string | undefined {
  const resolved = resolveConsumerDisplayFields(displayFields, {
    scope: {
      category: unit.category,
      geography: unit.geography,
      country: inferCountry(unit)
    },
    source: { key: spec.sourceKey },
    target: {
      key: spec.targetKey,
      environment: spec.targetEnvironment
    }
  });
  return resolved.find((field) => field.key === "poi_type")?.value;
}

function inferCountry(unit: BatchPlanUnit): string {
  if (unit.geographyKind === "country") {
    return unit.geography;
  }
  const parts = unit.geography.split("-");
  return parts.length > 1 ? parts[parts.length - 1]! : unit.geography;
}

export function formatBatchFullDataVolumeProjection(
  projection: BatchVolumeProjectionSpec | undefined
): string {
  if (!projection) {
    return "none declared";
  }
  const defaults = [
    projection.defaultSourceCandidatesPerUnit !== undefined
      ? `source=${projection.defaultSourceCandidatesPerUnit}`
      : null,
    projection.defaultExpectedTargetWritesPerUnit !== undefined
      ? `writes=${projection.defaultExpectedTargetWritesPerUnit}`
      : null
  ]
    .filter(Boolean)
    .join(", ");
  const categories = Object.keys(projection.byCategory ?? {}).sort().join(", ");
  return `defaults(${defaults || "inherit bounds"}) categories(${categories || "none"})`;
}
