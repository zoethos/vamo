/**
 * Batch target planner — pure expansion into deterministic dry-run units.
 *
 * No DB, network, or provider calls. Reuses schedule-proposal policy for each
 * planned unit when scorecard facts are available.
 */

import type { BatchPlanSpec, BatchPriorityHint } from "./batch-plan-spec.js";
import { BATCH_FORBIDDEN_SAFETY_MODES } from "./batch-plan-spec.js";
import {
  buildScheduleProposal,
  type ScheduleProposal,
  type ScheduleScope,
  type SafetyMode
} from "./schedule-proposal.js";
import {
  scoreTargetCandidate,
  type TargetCandidateInput,
  type TargetScorecard
} from "./target-scorecard.js";
import { isLegacyTargetKey } from "./target-identity.js";

export type BatchPlanUnitStatus = "planned" | "blocked";

export interface BatchPlanUnit {
  unitKey: string;
  runOrder: number;
  projectKey: string;
  targetId: string;
  targetProfileKey: string;
  sourceId: string;
  targetEnvironment: BatchPlanSpec["targetEnvironment"];
  geography: string;
  geographyKind: "country" | "region" | "city" | "area" | "bounding_box";
  category: string;
  safetyMode: SafetyMode;
  priority: number;
  status: BatchPlanUnitStatus;
  blockReasons: string[];
  scope: ScheduleScope;
  scorecard?: TargetScorecard;
  proposal?: ScheduleProposal;
}

export interface BatchCoverageSummary {
  perCountry: Record<string, number>;
  perCategory: Record<string, number>;
}

export interface BatchPlanResult {
  planId: string;
  projectKey: string;
  targetKey: string;
  targetEnvironment: BatchPlanSpec["targetEnvironment"];
  sourceKey: string;
  safetyMode: SafetyMode;
  totalUnits: number;
  plannedUnits: number;
  blockedUnits: number;
  units: BatchPlanUnit[];
  coverage: BatchCoverageSummary;
  nextAction: string;
}

export interface BuildBatchPlanInput {
  spec: BatchPlanSpec;
  /** Optional scorecard template applied to every generated unit. */
  candidateTemplate?: TargetCandidateInput;
  now?: string;
}

const DEFAULT_RUN_WINDOW = {
  earliestStart: "2026-07-01T00:00:00Z",
  latestStop: "2026-12-31T23:59:59Z"
};

export function buildBatchPlan(input: BuildBatchPlanInput): BatchPlanResult {
  const { spec } = input;
  assertSafeSpec(spec);

  const rowLimit = spec.bounds?.sampleRowLimitPerUnit ?? 50;
  const batchSize = spec.bounds?.defaultBatchSize ?? 10;
  const expanded = expandGeographies(spec);
  const categories = [...spec.categories].sort();
  const priorityHints = spec.priorityHints ?? [];
  const maxUnits = spec.bounds?.maxUnits;

  const rawUnits: BatchPlanUnit[] = [];
  for (const geography of expanded) {
    for (const category of categories) {
      const unitKey = `${spec.targetKey}:${geography.key}:${category}`;
      const blockReasons = validateUnit(spec, geography.key, category);
      const scope: ScheduleScope = {
        geography: geography.key,
        category,
        rowLimit,
        sourcePartition: spec.sourceKey,
        boundingBox: geography.boundingBox
      };
      const unit: BatchPlanUnit = {
        unitKey,
        runOrder: 0,
        projectKey: spec.projectKey,
        targetId: spec.targetKey,
        targetProfileKey: spec.targetProfileKey,
        sourceId: spec.sourceKey,
        targetEnvironment: spec.targetEnvironment,
        geography: geography.key,
        geographyKind: geography.kind,
        category,
        safetyMode: spec.safetyMode,
        priority: resolvePriority(geography.key, category, priorityHints),
        status: blockReasons.length > 0 ? "blocked" : "planned",
        blockReasons,
        scope
      };

      if (unit.status === "planned" && input.candidateTemplate) {
        attachProposal(unit, input.candidateTemplate, batchSize, input.now);
      }
      rawUnits.push(unit);
    }
  }

  const deduped = dedupeUnits(rawUnits);
  const limited =
    typeof maxUnits === "number" && maxUnits > 0 ? deduped.slice(0, maxUnits) : deduped;
  const ordered = assignRunOrder(limited);
  const plannedUnits = ordered.filter((unit) => unit.status === "planned").length;
  const blockedUnits = ordered.length - plannedUnits;

  return {
    planId: spec.id,
    projectKey: spec.projectKey,
    targetKey: spec.targetKey,
    targetEnvironment: spec.targetEnvironment,
    sourceKey: spec.sourceKey,
    safetyMode: spec.safetyMode,
    totalUnits: ordered.length,
    plannedUnits,
    blockedUnits,
    units: ordered,
    coverage: summarizeCoverage(ordered),
    nextAction:
      blockedUnits > 0
        ? `Review batch: ${blockedUnits} blocked unit(s) need scope/config fixes before dry-run approval.`
        : "Review batch and approve dry-run scheduling for planned units."
  };
}

interface ExpandedGeography {
  key: string;
  kind: BatchPlanUnit["geographyKind"];
  country?: string;
  boundingBox?: string;
}

function expandGeographies(spec: BatchPlanSpec): ExpandedGeography[] {
  const items: ExpandedGeography[] = [];
  for (const entry of spec.geographies.countries ?? []) {
    items.push({ key: entry.key, kind: "country", country: entry.key });
  }
  for (const entry of spec.geographies.regions ?? []) {
    items.push({ key: entry.key, kind: "region", country: entry.country });
  }
  for (const entry of spec.geographies.cities ?? []) {
    items.push({ key: entry.key, kind: "city", country: entry.country });
  }
  for (const entry of spec.geographies.areas ?? []) {
    items.push({ key: entry.key, kind: "area", country: entry.country });
  }
  for (const entry of spec.geographies.boundingBoxes ?? []) {
    items.push({
      key: entry.key,
      kind: "bounding_box",
      country: entry.country,
      boundingBox: entry.bounds
    });
  }
  return items.sort((a, b) => a.key.localeCompare(b.key) || a.kind.localeCompare(b.kind));
}

function dedupeUnits(units: BatchPlanUnit[]): BatchPlanUnit[] {
  const map = new Map<string, BatchPlanUnit>();
  for (const unit of units) {
    const dedupeKey = `${unit.geography}:${unit.category}`;
    const existing = map.get(dedupeKey);
    if (!existing) {
      map.set(dedupeKey, unit);
      continue;
    }
    if (existing.status === "blocked" && unit.status === "planned") {
      map.set(dedupeKey, unit);
      continue;
    }
    if (existing.status === unit.status && unit.priority > existing.priority) {
      map.set(dedupeKey, unit);
    }
  }
  return [...map.values()].sort((a, b) => {
    if (b.priority !== a.priority) {
      return b.priority - a.priority;
    }
    return a.unitKey.localeCompare(b.unitKey);
  });
}

function assignRunOrder(units: BatchPlanUnit[]): BatchPlanUnit[] {
  return units.map((unit, index) => ({ ...unit, runOrder: index + 1 }));
}

function validateUnit(spec: BatchPlanSpec, geography: string, category: string): string[] {
  const reasons: string[] = [];
  if (!geography) {
    reasons.push("missing_geography");
  }
  if (!category) {
    reasons.push("missing_category");
  }
  if (!spec.sourceKey) {
    reasons.push("missing_source_key");
  }
  if (!spec.targetProfileKey) {
    reasons.push("missing_target_profile");
  }
  if (isLegacyTargetKey(spec.targetKey)) {
    reasons.push("legacy_target_key_forbidden");
  }
  if (BATCH_FORBIDDEN_SAFETY_MODES.includes(spec.safetyMode)) {
    reasons.push("unsafe_safety_mode");
  }
  return reasons;
}

function attachProposal(
  unit: BatchPlanUnit,
  template: TargetCandidateInput,
  batchSize: number,
  now?: string
): void {
  const candidate: TargetCandidateInput = {
    ...template,
    targetId: unit.targetId,
    projectKey: unit.projectKey,
    sourceId: unit.sourceId,
    safetyMode: "dry_run"
  };
  const scorecard = scoreTargetCandidate(candidate);
  unit.scorecard = scorecard;
  const proposalResult = buildScheduleProposal({
    scorecard,
    tier: "sample_dry_run",
    safetyMode: "dry_run",
    scope: unit.scope,
    batchSize,
    checkpointEveryRows: Math.max(1, Math.floor(batchSize / 2)),
    quotaBudget: {
      maxRows: unit.scope.rowLimit,
      maxSourceCalls: 1,
      maxRuntimeSeconds: 120,
      maxFailures: 1
    },
    runWindow: {
      ...DEFAULT_RUN_WINDOW,
      latestStop: now ?? DEFAULT_RUN_WINDOW.latestStop
    },
    stopConditions: {
      maxPolicyBlockRate: 0.5,
      maxDeadLetterRate: 0.5,
      maxCollisionRate: 0.2,
      stopOnSchemaMismatch: true,
      stopOnTargetWriteFailure: true,
      honorOperatorPause: true
    },
    forbidNonDryRun: true
  });
  if (proposalResult.ok) {
    unit.proposal = proposalResult.proposal;
  } else {
    unit.status = "blocked";
    unit.blockReasons.push(...proposalResult.errors.map((error) => error.code));
  }
}

function resolvePriority(
  geography: string,
  category: string,
  hints: BatchPriorityHint[]
): number {
  let priority = 0;
  for (const hint of hints) {
    const geoMatch = !hint.geography || hint.geography === geography;
    const categoryMatch = !hint.category || hint.category === category;
    if (geoMatch && categoryMatch) {
      priority = Math.max(priority, hint.weight);
    }
  }
  return priority;
}

function summarizeCoverage(units: BatchPlanUnit[]): BatchCoverageSummary {
  const perCountry: Record<string, number> = {};
  const perCategory: Record<string, number> = {};
  for (const unit of units) {
    if (unit.status !== "planned") {
      continue;
    }
    const country = inferCountry(unit);
    perCountry[country] = (perCountry[country] ?? 0) + 1;
    perCategory[unit.category] = (perCategory[unit.category] ?? 0) + 1;
  }
  return { perCountry, perCategory };
}

function inferCountry(unit: BatchPlanUnit): string {
  if (unit.geographyKind === "country") {
    return unit.geography;
  }
  const parts = unit.geography.split("-");
  return parts.length > 1 ? parts[parts.length - 1]! : unit.geography;
}

function assertSafeSpec(spec: BatchPlanSpec): void {
  if (BATCH_FORBIDDEN_SAFETY_MODES.includes(spec.safetyMode) || spec.safetyMode !== "dry_run") {
    throw new Error(`Batch planning slice requires safetyMode=dry_run, not "${spec.safetyMode}".`);
  }
  if (isLegacyTargetKey(spec.targetKey)) {
    throw new Error("Batch plan targetKey must be environment-neutral.");
  }
}
