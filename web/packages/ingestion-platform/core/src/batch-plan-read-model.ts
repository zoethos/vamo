/**
 * Batch plan dashboard read model — pure transform for IP-18 preview.
 */

import { readFileSync } from "node:fs";

import type { BatchPlanResult, BatchPlanUnit } from "./batch-planner.js";
import { buildBatchPlan, type BuildBatchPlanInput } from "./batch-planner.js";
import { parseBatchPlanSpec, type BatchPlanSpec } from "./batch-plan-spec.js";
import type { TargetCandidateInput } from "./target-scorecard.js";

export interface BatchPlanRow {
  runOrder: number;
  unitKey: string;
  geography: string;
  category: string;
  targetEnvironment: string;
  priority: number;
  status: string;
  blockReasons: string[];
}

export interface BatchPlanView {
  planId: string;
  projectKey: string;
  targetKey: string;
  targetEnvironment: string;
  sourceKey: string;
  totalUnits: number;
  plannedUnits: number;
  blockedUnits: number;
  coverage: BatchPlanResult["coverage"];
  rows: BatchPlanRow[];
  previewRows: BatchPlanRow[];
  nextAction: string;
}

export function buildBatchPlanView(plan: BatchPlanResult, previewLimit = 8): BatchPlanView {
  const rows = plan.units.map(toRow);
  return {
    planId: plan.planId,
    projectKey: plan.projectKey,
    targetKey: plan.targetKey,
    targetEnvironment: plan.targetEnvironment,
    sourceKey: plan.sourceKey,
    totalUnits: plan.totalUnits,
    plannedUnits: plan.plannedUnits,
    blockedUnits: plan.blockedUnits,
    coverage: plan.coverage,
    rows,
    previewRows: rows.slice(0, previewLimit),
    nextAction: plan.nextAction
  };
}

export function buildBatchPlanFromSpec(input: BuildBatchPlanInput): BatchPlanResult {
  return buildBatchPlan(input);
}

export function sampleVamoEuPoiBatchYaml(): string {
  return SAMPLE_VAMO_EU_POI_BATCH_YAML;
}

export function sampleVamoEuPoiBatchPlan(candidateTemplate?: TargetCandidateInput): BatchPlanResult {
  const parsed = parseBatchPlanSpec(SAMPLE_VAMO_EU_POI_BATCH_YAML);
  if (!parsed.ok) {
    throw new Error(`Sample batch spec invalid: ${JSON.stringify(parsed.errors)}`);
  }
  return buildBatchPlan({
    spec: parsed.spec,
    candidateTemplate: candidateTemplate ?? sampleVamoCandidateTemplate()
  });
}

export function sampleVamoEuPoiBatchView(): BatchPlanView {
  return buildBatchPlanView(sampleVamoEuPoiBatchPlan());
}

export const VAMO_EU_FULL_DATA_BATCH_SPEC_PATH =
  "fixtures/platform/ip18/vamo-eu-full-data-batch.yaml";

export function loadVamoEuFullDataBatchYaml(
  rootDir = process.cwd()
): string {
  return readFileSync(`${rootDir}/${VAMO_EU_FULL_DATA_BATCH_SPEC_PATH}`, "utf8");
}

export function vamoEuFullDataBatchPlan(
  candidateTemplate?: TargetCandidateInput
): BatchPlanResult {
  const parsed = parseBatchPlanSpec(loadVamoEuFullDataBatchYaml());
  if (!parsed.ok) {
    throw new Error(`Full-data batch spec invalid: ${JSON.stringify(parsed.errors)}`);
  }
  return buildBatchPlan({
    spec: parsed.spec,
    candidateTemplate: candidateTemplate ?? sampleVamoCandidateTemplate()
  });
}

function toRow(unit: BatchPlanUnit): BatchPlanRow {
  return {
    runOrder: unit.runOrder,
    unitKey: unit.unitKey,
    geography: unit.geography,
    category: unit.category,
    targetEnvironment: unit.targetEnvironment,
    priority: unit.priority,
    status: unit.status,
    blockReasons: unit.blockReasons.slice()
  };
}

function sampleVamoCandidateTemplate(): TargetCandidateInput {
  return {
    targetId: "vamo-place-intelligence",
    projectKey: "vamo",
    sourceId: "fsq-os-places-sample",
    safetyMode: "dry_run",
    consumerValue: {
      useCase: "Seed Vamo place cache for EU POI coverage.",
      reducesLiveCalls: true
    },
    sourceRights: {
      canStoreFacts: true,
      attributionPresent: true,
      retentionDeclared: true,
      liveOnly: false
    },
    targetReadiness: {
      schemaCompatible: true,
      upsertKeysDeclared: true,
      rlsPostureOk: true,
      stagingEnvironmentExists: true
    },
    dataQuality: { requiredFieldsPresent: true, coordinatesValid: true, sampleRowCount: 3 },
    checkpointability: { cursorStrategyDeclared: true, resumeTested: true },
    costAndQuota: { rowLimitDeclared: true, stopConditionsDeclared: true, withinBudget: true },
    collision: { policy: "review" },
    blastRadius: { bounded: true, firstShipmentStagingOnly: true },
    observability: {
      eventsAvailable: true,
      checkpointsAvailable: true,
      deadLettersAvailable: true,
      statsAvailable: true
    }
  };
}

const SAMPLE_VAMO_EU_POI_BATCH_YAML = `kind: ingestion.batch_plan
version: 1
id: vamo-eu-poi-sample
projectKey: vamo
sourceKey: fsq-os-places-sample
targetProfileKey: place-intelligence
targetKey: vamo-place-intelligence
targetEnvironment: staging
safetyMode: dry_run
notes: >
  Representative EU POI batch sample for IP-18 planning only. Full EU coverage
  will come from open-source snapshots such as FSQ OS Places, GeoNames, and
  Wikidata in later slices — not from this tiny fixture.
geographies:
  countries:
    - key: italy
      label: Italy
    - key: france
      label: France
    - key: germany
      label: Germany
    - key: spain
      label: Spain
  regions:
    - key: lombardy-italy
      country: italy
      label: Lombardy
  cities:
    - key: rome-italy
      country: italy
      label: Rome
    - key: paris-france
      country: france
      label: Paris
    - key: munich-germany
      country: germany
      label: Munich
    - key: barcelona-spain
      country: spain
      label: Barcelona
categories:
  - poi
  - landmark
  - restaurant
  - transport
priorityHints:
  - geography: rome-italy
    category: poi
    weight: 10
  - geography: paris-france
    category: landmark
    weight: 8
bounds:
  sampleRowLimitPerUnit: 50
  defaultBatchSize: 10
`;
