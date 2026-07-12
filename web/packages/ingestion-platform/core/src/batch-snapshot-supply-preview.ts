/**
 * Batch snapshot supply preview — pure read model for IP-18.8.1.
 *
 * Binds a planned batch queue to local snapshot rows per unit. No DB, network,
 * provider calls, or target writes.
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import type { BatchPlanResult, BatchPlanUnit } from "./batch-planner.js";
import type { BatchPlanSpec } from "./batch-plan-spec.js";
import { resolveUnitVolume } from "./batch-full-data-plan-preview.js";
import {
  buildBatchQueueSnapshotFromItems,
  formatParkedEmptySourceScopesMessage,
  type BatchQueueItem,
  type BatchQueueItemStatus,
  type BatchQueueSnapshot
} from "./batch-queue-read-model.js";
import { resolveDefaultBatchQueueDisplayFields } from "./consumer-display-fields.js";

export type BatchSnapshotSupplyState = "supply_ready" | "supply_empty" | "supply_invalid";

export type BatchSnapshotSupplySeedMode = "block_empty_units" | "include_empty_units";

export const BATCH_SNAPSHOT_EMPTY_BLOCK_REASON = "source_snapshot_empty" as const;
export const BATCH_SNAPSHOT_INVALID_BLOCK_REASON = "source_snapshot_invalid" as const;

export interface BatchSnapshotSourceRow {
  scope?: {
    geography?: string;
    category?: string;
  };
  attribution?: string;
  source?: Record<string, unknown>;
  media?: Record<string, unknown>;
}

export interface BatchSnapshotSupplyUnitView {
  unitKey: string;
  geography: string;
  category: string;
  country: string;
  recommendedQueueStatus: BatchQueueItemStatus;
  sourceRowCount: number;
  validSourceRowCount: number;
  invalidSourceRowCount: number;
  expectedTargetWrites: number;
  supplyState: BatchSnapshotSupplyState;
  blockReasons: string[];
  operatorLabels: string[];
}

export interface BatchSnapshotSupplySummary {
  actualSourceRows: number;
  validSourceRows: number;
  invalidSourceRows: number;
  totalPlannedUnits: number;
  unitsWithSourceRows: number;
  unitsWithoutSourceRows: number;
  unitsWithInvalidRowsOnly: number;
  rowsByCountry: Record<string, number>;
  rowsByCategory: Record<string, number>;
}

export interface BatchSnapshotSupplyPreview {
  summary: BatchSnapshotSupplySummary;
  perUnit: BatchSnapshotSupplyUnitView[];
  emptyUnits: BatchSnapshotSupplyUnitView[];
  supplyReadyUnits: BatchSnapshotSupplyUnitView[];
  defaultSeedMode: BatchSnapshotSupplySeedMode;
  defaultSeedBlockReason: typeof BATCH_SNAPSHOT_EMPTY_BLOCK_REASON;
}

export interface BuildBatchSnapshotSupplyPreviewInput {
  plan: BatchPlanResult;
  spec: BatchPlanSpec;
  rows: readonly BatchSnapshotSourceRow[];
}

export interface ApplySnapshotSupplyBindingInput {
  snapshot: BatchQueueSnapshot;
  supplyPreview: BatchSnapshotSupplyPreview;
  seedMode?: BatchSnapshotSupplySeedMode;
}

export function readSnapshotSourceRowsFromSpec(
  spec: BatchPlanSpec,
  rootDir = process.cwd()
): BatchSnapshotSourceRow[] | undefined {
  const snapshotPath = spec.source?.connection?.snapshotPath;
  if (typeof snapshotPath !== "string" || snapshotPath.trim().length === 0) {
    return undefined;
  }
  const absolutePath = resolve(rootDir, snapshotPath);
  return readFileSync(absolutePath, "utf8")
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line) as BatchSnapshotSourceRow);
}

export function buildBatchSnapshotSupplyPreview(
  input: BuildBatchSnapshotSupplyPreviewInput
): BatchSnapshotSupplyPreview {
  const rowsByScope = indexRowsByScope(input.rows);
  const perUnit = input.plan.units
    .filter((unit) => unit.status === "planned")
    .map((unit) => buildUnitSupplyView(unit, input.spec, rowsByScope));

  const emptyUnits = perUnit.filter((unit) => unit.supplyState === "supply_empty");
  const supplyReadyUnits = perUnit.filter((unit) => unit.supplyState === "supply_ready");

  return {
    summary: summarizeSupply(perUnit, input.rows),
    perUnit,
    emptyUnits,
    supplyReadyUnits,
    defaultSeedMode: "block_empty_units",
    defaultSeedBlockReason: BATCH_SNAPSHOT_EMPTY_BLOCK_REASON
  };
}

export function applySnapshotSupplyToQueueSnapshot(
  input: ApplySnapshotSupplyBindingInput
): BatchQueueSnapshot {
  const seedMode = input.seedMode ?? input.supplyPreview.defaultSeedMode;
  if (seedMode === "include_empty_units") {
    return input.snapshot;
  }

  const supplyByUnitKey = new Map(input.supplyPreview.perUnit.map((unit) => [unit.unitKey, unit]));
  const items = input.snapshot.items.map((item) => {
    const supply = supplyByUnitKey.get(item.unitKey);
    if (!supply) {
      return item;
    }
    return applySupplyBindingToQueueItem(item, supply);
  });

  return buildBatchQueueSnapshotFromItems({
    planId: input.snapshot.planId,
    projectKey: input.snapshot.projectKey,
    targetKey: input.snapshot.targetKey,
    targetEnvironment: input.snapshot.targetEnvironment,
    sourceKey: input.snapshot.sourceKey,
    safetyMode: input.snapshot.safetyMode,
    items,
    planNextAction: buildSupplyAwareNextAction(input.snapshot.nextAction, input.supplyPreview),
    latestExecution: input.snapshot.latestExecution,
    latestWave: input.snapshot.latestWave,
    latestProductionPackageWave: input.snapshot.latestProductionPackageWave,
    displayFields: resolveDefaultBatchQueueDisplayFields({
      projectKey: input.snapshot.projectKey,
      targetKey: input.snapshot.targetKey
    })
  });
}

export function buildBatchQueueSnapshotWithSupplyBinding(input: {
  plan: BatchPlanResult;
  spec: BatchPlanSpec;
  rows: readonly BatchSnapshotSourceRow[];
  seedMode?: BatchSnapshotSupplySeedMode;
  supplyPreview?: BatchSnapshotSupplyPreview;
}): { snapshot: BatchQueueSnapshot; supplyPreview: BatchSnapshotSupplyPreview } {
  const supplyPreview =
    input.supplyPreview ??
    buildBatchSnapshotSupplyPreview({
      plan: input.plan,
      spec: input.spec,
      rows: input.rows
    });
  const baseSnapshot = buildBatchQueueSnapshotFromItems({
    planId: input.plan.planId,
    projectKey: input.plan.projectKey,
    targetKey: input.plan.targetKey,
    targetEnvironment: input.plan.targetEnvironment,
    sourceKey: input.plan.sourceKey,
    safetyMode: input.plan.safetyMode,
    items: input.plan.units.map((unit) => planUnitToQueueItem(unit, input.plan)),
    planNextAction: input.plan.nextAction,
    displayFields: resolveDefaultBatchQueueDisplayFields({
      projectKey: input.plan.projectKey,
      targetKey: input.plan.targetKey
    })
  });
  const snapshot = applySnapshotSupplyToQueueSnapshot({
    snapshot: baseSnapshot,
    supplyPreview,
    seedMode: input.seedMode
  });
  return { snapshot, supplyPreview };
}

export function summarizeSnapshotSupplyCounts(
  units: readonly BatchPlanUnit[],
  rows: readonly BatchSnapshotSourceRow[]
): Pick<
  BatchSnapshotSupplySummary,
  "actualSourceRows" | "unitsWithSourceRows" | "unitsWithoutSourceRows"
> {
  const rowsByScope = indexRowsByScope(rows);
  let unitsWithSourceRows = 0;
  let unitsWithoutSourceRows = 0;
  for (const unit of units) {
    if (unit.status !== "planned") {
      continue;
    }
    const scopeKey = snapshotScopeKey(unit.geography, unit.category);
    const scoped = rowsByScope.get(scopeKey);
    const validCount = scoped?.validRows.length ?? 0;
    if (validCount > 0) {
      unitsWithSourceRows += 1;
    } else {
      unitsWithoutSourceRows += 1;
    }
  }
  return {
    actualSourceRows: rows.length,
    unitsWithSourceRows,
    unitsWithoutSourceRows
  };
}

interface ScopedSnapshotRows {
  rows: BatchSnapshotSourceRow[];
  validRows: BatchSnapshotSourceRow[];
  invalidRows: Array<{ row: BatchSnapshotSourceRow; reason: string }>;
}

function buildUnitSupplyView(
  unit: BatchPlanUnit,
  spec: BatchPlanSpec,
  rowsByScope: Map<string, ScopedSnapshotRows>
): BatchSnapshotSupplyUnitView {
  const scopeKey = snapshotScopeKey(unit.geography, unit.category);
  const scoped = rowsByScope.get(scopeKey) ?? { rows: [], validRows: [], invalidRows: [] };
  const expectedTargetWrites = resolveUnitVolume(spec, unit.category).expectedTargetWrites;
  const country = inferCountry(unit);

  let supplyState: BatchSnapshotSupplyState;
  const blockReasons: string[] = [];
  const operatorLabels: string[] = [];

  if (scoped.validRows.length > 0) {
    supplyState = "supply_ready";
    operatorLabels.push(`${scoped.validRows.length} local snapshot row(s) available`);
  } else if (scoped.rows.length > 0) {
    supplyState = "supply_invalid";
    blockReasons.push(BATCH_SNAPSHOT_INVALID_BLOCK_REASON);
    for (const reason of [...new Set(scoped.invalidRows.map((entry) => entry.reason))].sort()) {
      blockReasons.push(reason);
      operatorLabels.push(formatInvalidReasonLabel(reason));
    }
  } else {
    supplyState = "supply_empty";
    blockReasons.push(BATCH_SNAPSHOT_EMPTY_BLOCK_REASON);
    operatorLabels.push("No local snapshot rows for this geography/category scope");
  }

  const recommendedQueueStatus = resolveRecommendedQueueStatus(unit, supplyState);

  return {
    unitKey: unit.unitKey,
    geography: unit.geography,
    category: unit.category,
    country,
    recommendedQueueStatus,
    sourceRowCount: scoped.rows.length,
    validSourceRowCount: scoped.validRows.length,
    invalidSourceRowCount: scoped.invalidRows.length,
    expectedTargetWrites,
    supplyState,
    blockReasons,
    operatorLabels
  };
}

function summarizeSupply(
  perUnit: readonly BatchSnapshotSupplyUnitView[],
  rows: readonly BatchSnapshotSourceRow[]
): BatchSnapshotSupplySummary {
  const rowsByCountry: Record<string, number> = {};
  const rowsByCategory: Record<string, number> = {};
  let validSourceRows = 0;
  let invalidSourceRows = 0;

  for (const row of rows) {
    const classification = classifySnapshotRow(row);
    if (classification.valid) {
      validSourceRows += 1;
      const geography = row.scope?.geography?.trim();
      const category = row.scope?.category?.trim();
      if (geography && category) {
        const country = inferCountryFromGeography(geography);
        rowsByCountry[country] = (rowsByCountry[country] ?? 0) + 1;
        rowsByCategory[category] = (rowsByCategory[category] ?? 0) + 1;
      }
    } else {
      invalidSourceRows += 1;
    }
  }

  return {
    actualSourceRows: rows.length,
    validSourceRows,
    invalidSourceRows,
    totalPlannedUnits: perUnit.length,
    unitsWithSourceRows: perUnit.filter((unit) => unit.supplyState === "supply_ready").length,
    unitsWithoutSourceRows: perUnit.filter((unit) => unit.supplyState === "supply_empty").length,
    unitsWithInvalidRowsOnly: perUnit.filter((unit) => unit.supplyState === "supply_invalid").length,
    rowsByCountry,
    rowsByCategory
  };
}

function indexRowsByScope(rows: readonly BatchSnapshotSourceRow[]): Map<string, ScopedSnapshotRows> {
  const map = new Map<string, ScopedSnapshotRows>();
  for (const row of rows) {
    const geography = row.scope?.geography?.trim();
    const category = row.scope?.category?.trim();
    if (!geography || !category) {
      continue;
    }
    const key = snapshotScopeKey(geography, category);
    const bucket = map.get(key) ?? { rows: [], validRows: [], invalidRows: [] };
    bucket.rows.push(row);
    const classification = classifySnapshotRow(row);
    if (classification.valid) {
      bucket.validRows.push(row);
    } else {
      bucket.invalidRows.push({ row, reason: classification.reason ?? "invalid_snapshot_row" });
    }
    map.set(key, bucket);
  }
  return map;
}

function classifySnapshotRow(row: BatchSnapshotSourceRow): { valid: boolean; reason?: string } {
  if (!row || typeof row !== "object") {
    return { valid: false, reason: "invalid_record_shape" };
  }
  if (!readString(row.attribution)) {
    return { valid: false, reason: "missing_attribution" };
  }
  const geography = row.scope?.geography?.trim();
  const category = row.scope?.category?.trim();
  if (!geography || !category) {
    return { valid: false, reason: "missing_scope_fields" };
  }
  if (!row.source || typeof row.source !== "object") {
    return { valid: false, reason: "missing_source_object" };
  }
  if (row.media && typeof row.media === "object" && row.media.bytesBase64) {
    return { valid: false, reason: "media_bytes_forbidden" };
  }
  return { valid: true };
}

function resolveRecommendedQueueStatus(
  unit: BatchPlanUnit,
  supplyState: BatchSnapshotSupplyState
): BatchQueueItemStatus {
  if (unit.status === "blocked") {
    return "blocked";
  }
  if (supplyState === "supply_empty" || supplyState === "supply_invalid") {
    return "blocked";
  }
  if (unit.proposal) {
    return "ready_for_dry_run";
  }
  return "planned";
}

function applySupplyBindingToQueueItem(
  item: BatchQueueItem,
  supply: BatchSnapshotSupplyUnitView
): BatchQueueItem {
  if (supply.supplyState === "supply_ready") {
    return item;
  }
  const blockReasons = [...new Set([...item.blockReasons, ...supply.blockReasons])];
  return {
    ...item,
    status: "blocked",
    blockReasons,
    proposal: null
  };
}

function planUnitToQueueItem(unit: BatchPlanUnit, plan: BatchPlanResult): BatchQueueItem {
  const country = inferCountry(unit);
  return {
    unitKey: unit.unitKey,
    runOrder: unit.runOrder,
    geography: unit.geography,
    geographyKind: unit.geographyKind,
    country,
    category: unit.category,
    targetKey: plan.targetKey,
    targetEnvironment: plan.targetEnvironment,
    sourceKey: plan.sourceKey,
    priority: unit.priority,
    status: unit.status === "blocked" ? "blocked" : unit.proposal ? "ready_for_dry_run" : "planned",
    blockReasons: unit.blockReasons.slice(),
    proposal: unit.proposal ? ({ ...unit.proposal } as Record<string, unknown>) : null
  };
}

function buildSupplyAwareNextAction(
  baseNextAction: string,
  supplyPreview: BatchSnapshotSupplyPreview
): string {
  if (supplyPreview.summary.unitsWithoutSourceRows === 0) {
    return baseNextAction;
  }
  return formatParkedEmptySourceScopesMessage(supplyPreview.summary.unitsWithoutSourceRows);
}

function snapshotScopeKey(geography: string, category: string): string {
  return `${geography.trim().toLowerCase()}:${category.trim().toLowerCase()}`;
}

function inferCountry(unit: BatchPlanUnit): string {
  if (unit.geographyKind === "country") {
    return unit.geography;
  }
  return inferCountryFromGeography(unit.geography);
}

function inferCountryFromGeography(geography: string): string {
  const parts = geography.split("-");
  return parts.length > 1 ? parts[parts.length - 1]! : geography;
}

function formatInvalidReasonLabel(reason: string): string {
  switch (reason) {
    case "missing_attribution":
      return "Matching rows missing attribution";
    case "media_bytes_forbidden":
      return "Matching rows contain forbidden media bytes";
    case "missing_scope_fields":
      return "Matching rows missing scope geography/category";
    case "missing_source_object":
      return "Matching rows missing source object";
    default:
      return `Matching rows failed ${reason}`;
  }
}

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}
