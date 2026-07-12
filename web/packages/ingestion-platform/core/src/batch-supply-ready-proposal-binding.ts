/**
 * Supply-ready schedule proposal binding — pure helper for IP-18.8.2.
 *
 * Attaches bounded dry-run ScheduleProposal objects only to units with verified
 * local snapshot rows. No DB, network, provider calls, or target writes.
 */

import type { BatchPlanResult, BatchPlanUnit } from "./batch-planner.js";
import type { BatchDryRunProposalFactsSpec, BatchPlanSpec } from "./batch-plan-spec.js";
import {
  buildScheduleProposal,
  type ScheduleProposal
} from "./schedule-proposal.js";
import {
  scoreTargetCandidate,
  type TargetCandidateInput,
  type TargetScorecard
} from "./target-scorecard.js";
import {
  buildBatchQueueSnapshotWithSupplyBinding,
  type BatchSnapshotSourceRow,
  type BatchSnapshotSupplyPreview,
  type BatchSnapshotSupplySeedMode,
  buildBatchSnapshotSupplyPreview
} from "./batch-snapshot-supply-preview.js";
import {
  formatParkedEmptySourceScopesMessage,
  type BatchQueueSnapshot
} from "./batch-queue-read-model.js";
import { buildBatchPlan } from "./batch-planner.js";

const DEFAULT_RUN_WINDOW = {
  earliestStart: "2026-07-01T00:00:00Z",
  latestStop: "2026-12-31T23:59:59Z"
};

export interface BindSupplyReadyScheduleProposalsInput {
  spec: BatchPlanSpec;
  plan: BatchPlanResult;
  supplyPreview: BatchSnapshotSupplyPreview;
  now?: string;
}

export interface BuildFullDataBoundBatchQueueSnapshotInput {
  spec: BatchPlanSpec;
  rows: readonly BatchSnapshotSourceRow[];
  seedMode?: BatchSnapshotSupplySeedMode;
  now?: string;
}

export function bindSupplyReadyScheduleProposals(
  input: BindSupplyReadyScheduleProposalsInput
): BatchPlanResult {
  const supplyByUnitKey = new Map(input.supplyPreview.perUnit.map((unit) => [unit.unitKey, unit]));
  const defaultBatchSize = input.spec.bounds?.defaultBatchSize ?? 10;
  const specRowBound = input.spec.bounds?.sampleRowLimitPerUnit ?? 50;
  const facts = resolveDryRunProposalFacts(input.spec);

  const units = input.plan.units.map((unit) => {
    if (unit.status !== "planned") {
      return cloneUnitWithoutProposal(unit);
    }

    const supply = supplyByUnitKey.get(unit.unitKey);
    if (!supply || supply.supplyState !== "supply_ready") {
      return cloneUnitWithoutProposal(unit);
    }

    const rowLimit = Math.min(specRowBound, supply.validSourceRowCount);
    if (rowLimit <= 0) {
      return cloneUnitWithoutProposal(unit);
    }

    const batchSize = Math.max(1, Math.min(defaultBatchSize, rowLimit));
    const scopedUnit: BatchPlanUnit = {
      ...unit,
      scope: {
        ...unit.scope,
        rowLimit
      }
    };

    attachSupplyReadyProposal({
      unit: scopedUnit,
      spec: input.spec,
      facts,
      validSourceRowCount: supply.validSourceRowCount,
      batchSize,
      rowLimit,
      now: input.now
    });

    return scopedUnit;
  });

  return {
    ...input.plan,
    units,
    nextAction: summarizeProposalBindingNextAction(input.plan.nextAction, units, input.supplyPreview)
  };
}

export function buildFullDataBoundBatchQueueSnapshot(
  input: BuildFullDataBoundBatchQueueSnapshotInput
): {
  snapshot: BatchQueueSnapshot;
  supplyPreview: BatchSnapshotSupplyPreview;
  plan: BatchPlanResult;
} {
  const basePlan = buildBatchPlan({ spec: input.spec });
  const supplyPreview = buildBatchSnapshotSupplyPreview({
    plan: basePlan,
    spec: input.spec,
    rows: input.rows
  });
  const plan = bindSupplyReadyScheduleProposals({
    spec: input.spec,
    plan: basePlan,
    supplyPreview,
    now: input.now
  });
  const { snapshot } = buildBatchQueueSnapshotWithSupplyBinding({
    plan,
    spec: input.spec,
    rows: input.rows,
    seedMode: input.seedMode,
    supplyPreview
  });

  return { snapshot, supplyPreview, plan };
}

export function resolveDryRunProposalFacts(spec: BatchPlanSpec): BatchDryRunProposalFactsSpec {
  if (spec.dryRunProposalFacts) {
    return spec.dryRunProposalFacts;
  }
  if (spec.consumerContractRef === "vamo-place-intelligence") {
    return defaultVamoPlaceIntelligenceProposalFacts();
  }
  return defaultSnapshotBackedProposalFacts();
}

function attachSupplyReadyProposal(input: {
  unit: BatchPlanUnit;
  spec: BatchPlanSpec;
  facts: BatchDryRunProposalFactsSpec;
  validSourceRowCount: number;
  batchSize: number;
  rowLimit: number;
  now?: string;
}): void {
  const candidate = buildProposalCandidate(input.unit, input.spec, input.facts, input.validSourceRowCount);
  const scorecard = scoreTargetCandidate(candidate);
  input.unit.scorecard = scorecard;

  const proposalResult = buildScheduleProposal({
    scorecard,
    tier: "sample_dry_run",
    safetyMode: "dry_run",
    scope: input.unit.scope,
    batchSize: input.batchSize,
    checkpointEveryRows: Math.max(1, Math.floor(input.batchSize / 2)),
    quotaBudget: {
      maxRows: input.rowLimit,
      maxSourceCalls: 1,
      maxRuntimeSeconds: 120,
      maxFailures: 1
    },
    runWindow: {
      ...DEFAULT_RUN_WINDOW,
      latestStop: input.now ?? DEFAULT_RUN_WINDOW.latestStop
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
    input.unit.proposal = proposalResult.proposal;
    return;
  }

  input.unit.status = "blocked";
  input.unit.blockReasons = [
    ...input.unit.blockReasons,
    ...proposalResult.errors.map((error) => error.code)
  ];
  input.unit.proposal = undefined;
  input.unit.scorecard = scorecard;
}

function buildProposalCandidate(
  unit: BatchPlanUnit,
  spec: BatchPlanSpec,
  facts: BatchDryRunProposalFactsSpec,
  validSourceRowCount: number
): TargetCandidateInput {
  return {
    targetId: unit.targetId,
    projectKey: unit.projectKey,
    sourceId: unit.sourceId,
    safetyMode: "dry_run",
    consumerValue: {
      useCase:
        facts.consumerValue?.useCase ??
        `Bounded dry-run over bundled snapshot rows for ${spec.targetKey}.`,
      reducesLiveCalls: facts.consumerValue?.reducesLiveCalls ?? true
    },
    sourceRights: {
      canStoreFacts: facts.sourceRights?.canStoreFacts ?? true,
      attributionPresent: facts.sourceRights?.attributionPresent ?? true,
      retentionDeclared: facts.sourceRights?.retentionDeclared ?? true,
      liveOnly: facts.sourceRights?.liveOnly ?? false
    },
    targetReadiness: {
      schemaCompatible: facts.targetReadiness?.schemaCompatible ?? true,
      upsertKeysDeclared: facts.targetReadiness?.upsertKeysDeclared ?? true,
      rlsPostureOk: facts.targetReadiness?.rlsPostureOk ?? true,
      stagingEnvironmentExists: facts.targetReadiness?.stagingEnvironmentExists ?? true
    },
    dataQuality: {
      requiredFieldsPresent: facts.dataQuality?.requiredFieldsPresent ?? true,
      coordinatesValid: facts.dataQuality?.coordinatesValid ?? true,
      sampleRowCount: validSourceRowCount
    },
    checkpointability: {
      cursorStrategyDeclared: facts.checkpointability?.cursorStrategyDeclared ?? true,
      resumeTested: facts.checkpointability?.resumeTested ?? true
    },
    costAndQuota: {
      rowLimitDeclared: facts.costAndQuota?.rowLimitDeclared ?? true,
      stopConditionsDeclared: facts.costAndQuota?.stopConditionsDeclared ?? true,
      withinBudget: facts.costAndQuota?.withinBudget ?? true
    },
    collision: {
      policy: facts.collision?.policy ?? "review"
    },
    blastRadius: {
      bounded: facts.blastRadius?.bounded ?? true,
      firstShipmentStagingOnly: facts.blastRadius?.firstShipmentStagingOnly ?? true
    },
    observability: {
      eventsAvailable: facts.observability?.eventsAvailable ?? true,
      checkpointsAvailable: facts.observability?.checkpointsAvailable ?? true,
      deadLettersAvailable: facts.observability?.deadLettersAvailable ?? true,
      statsAvailable: facts.observability?.statsAvailable ?? true
    }
  };
}

function cloneUnitWithoutProposal(unit: BatchPlanUnit): BatchPlanUnit {
  return {
    ...unit,
    proposal: undefined,
    scorecard: undefined
  };
}

function summarizeProposalBindingNextAction(
  baseNextAction: string,
  units: BatchPlanUnit[],
  supplyPreview: BatchSnapshotSupplyPreview
): string {
  const proposalBacked = units.filter((unit) => unit.proposal).length;
  if (proposalBacked === 0) {
    return baseNextAction;
  }
  if (supplyPreview.summary.unitsWithoutSourceRows > 0) {
    return `Review ${proposalBacked} proposal-backed supply-ready unit(s). ${formatParkedEmptySourceScopesMessage(supplyPreview.summary.unitsWithoutSourceRows)}`;
  }
  return `Review ${proposalBacked} proposal-backed supply-ready unit(s) for dry-run scheduling.`;
}

function defaultVamoPlaceIntelligenceProposalFacts(): BatchDryRunProposalFactsSpec {
  return {
    consumerValue: {
      useCase:
        "Bounded dry-run over bundled FSQ OS Places snapshot rows for Vamo place intelligence staging.",
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
    checkpointability: {
      cursorStrategyDeclared: true,
      resumeTested: true
    },
    costAndQuota: {
      rowLimitDeclared: true,
      stopConditionsDeclared: true,
      withinBudget: true
    },
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

function defaultSnapshotBackedProposalFacts(): BatchDryRunProposalFactsSpec {
  return defaultVamoPlaceIntelligenceProposalFacts();
}

export function serializeScheduleProposal(
  proposal: ScheduleProposal | undefined
): Record<string, unknown> | null {
  return proposal ? ({ ...proposal } as Record<string, unknown>) : null;
}

export function readProposalRowLimit(proposal: ScheduleProposal | undefined): number | undefined {
  return proposal?.scope.rowLimit;
}

export function readProposalQuotaMaxRows(proposal: ScheduleProposal | undefined): number | undefined {
  return proposal?.quotaBudget.maxRows;
}
