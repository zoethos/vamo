/**
 * Target selection scorecard — pure, deterministic policy.
 *
 * Implements the selection criteria in
 * docs/platform/ingestion/TARGET_SELECTION_AND_SCHEDULING.md §1. Every candidate
 * target is scored against the same criteria before it can move from `proposed`
 * to `scheduled`. Each criterion is a hard gate: if a gate fails, the target is
 * not eligible for scheduling regardless of its weighted score.
 *
 * This module is consumer-neutral. It scores declared *facts* about a candidate
 * target; it never imports a consumer profile, product table, or live source.
 * Keep it dependency-free (no node/pg/fs) so it is portable and browser-safe.
 */

import type { SafetyMode } from "./schedule-proposal.js";

/** The nine selection criteria, in canonical scorecard order. */
export const TARGET_SCORE_CRITERIA = [
  "consumer_value",
  "source_rights",
  "target_readiness",
  "data_quality",
  "checkpointability",
  "cost_and_quota",
  "collision_risk",
  "blast_radius",
  "observability"
] as const;

export type TargetScoreCriterion = (typeof TARGET_SCORE_CRITERIA)[number];

/** Relative weight of each criterion in the 0..1 weighted score. */
const CRITERION_WEIGHTS: Record<TargetScoreCriterion, number> = {
  consumer_value: 0.2,
  source_rights: 0.18,
  target_readiness: 0.16,
  data_quality: 0.12,
  checkpointability: 0.08,
  cost_and_quota: 0.08,
  collision_risk: 0.08,
  blast_radius: 0.06,
  observability: 0.04
};

export type CollisionPolicy = "auto" | "review" | "block" | "none";

export interface ConsumerValueFacts {
  /** A consumer owner must name the use case (hard gate). */
  useCase?: string;
  /** Does this reduce paid/live provider calls or unlock a product capability? */
  reducesLiveCalls: boolean;
}

export interface SourceRightsFacts {
  canStoreFacts: boolean;
  attributionPresent: boolean;
  retentionDeclared: boolean;
  /** Live-only sources cannot seed a durable cache (hard gate when storing). */
  liveOnly: boolean;
}

export interface TargetReadinessFacts {
  schemaCompatible: boolean;
  upsertKeysDeclared: boolean;
  rlsPostureOk: boolean;
  stagingEnvironmentExists: boolean;
}

export interface DataQualityFacts {
  requiredFieldsPresent: boolean;
  coordinatesValid: boolean;
  /** Rows available in the scouted sample. */
  sampleRowCount: number;
}

export interface CheckpointabilityFacts {
  cursorStrategyDeclared: boolean;
  resumeTested: boolean;
}

export interface CostAndQuotaFacts {
  rowLimitDeclared: boolean;
  stopConditionsDeclared: boolean;
  withinBudget: boolean;
}

export interface CollisionFacts {
  policy: CollisionPolicy;
}

export interface BlastRadiusFacts {
  bounded: boolean;
  firstShipmentStagingOnly: boolean;
}

export interface ObservabilityFacts {
  eventsAvailable: boolean;
  checkpointsAvailable: boolean;
  deadLettersAvailable: boolean;
  statsAvailable: boolean;
}

/** Declared facts about a candidate ingestion target. Consumer-neutral data. */
export interface TargetCandidateInput {
  targetId: string;
  projectKey: string;
  sourceId: string;
  /** Requested safety mode for the first run; gates scheduling eligibility. */
  safetyMode: SafetyMode;
  consumerValue: ConsumerValueFacts;
  sourceRights: SourceRightsFacts;
  targetReadiness: TargetReadinessFacts;
  dataQuality: DataQualityFacts;
  checkpointability: CheckpointabilityFacts;
  costAndQuota: CostAndQuotaFacts;
  collision: CollisionFacts;
  blastRadius: BlastRadiusFacts;
  observability: ObservabilityFacts;
}

export interface ScorecardCriterionResult {
  criterion: TargetScoreCriterion;
  /** 0..1 normalized contribution before weighting. */
  score: number;
  weight: number;
  /** A hard gate must pass for the target to be schedulable. */
  hardGate: boolean;
  gatePassed: boolean;
  reason: string;
}

export interface TargetScorecard {
  targetId: string;
  projectKey: string;
  sourceId: string;
  safetyMode: SafetyMode;
  /** Weighted 0..1 score, rounded to 4 dp for deterministic comparisons. */
  score: number;
  criteria: ScorecardCriterionResult[];
  /** True only when every hard gate passes. */
  eligibleForScheduling: boolean;
  /** Criteria whose hard gate failed, in canonical order. */
  blockingGates: TargetScoreCriterion[];
  /** Human-readable summary of why the target is (not) schedulable. */
  rationale: string;
}

/** Score a single candidate target. Pure and deterministic. */
export function scoreTargetCandidate(input: TargetCandidateInput): TargetScorecard {
  const criteria: ScorecardCriterionResult[] = [
    evaluateConsumerValue(input),
    evaluateSourceRights(input),
    evaluateTargetReadiness(input),
    evaluateDataQuality(input),
    evaluateCheckpointability(input),
    evaluateCostAndQuota(input),
    evaluateCollisionRisk(input),
    evaluateBlastRadius(input),
    evaluateObservability(input)
  ];

  const blockingGates = criteria
    .filter((result) => result.hardGate && !result.gatePassed)
    .map((result) => result.criterion);

  const weightedScore = criteria.reduce(
    (sum, result) => sum + result.score * result.weight,
    0
  );

  const eligibleForScheduling = blockingGates.length === 0;

  return {
    targetId: input.targetId,
    projectKey: input.projectKey,
    sourceId: input.sourceId,
    safetyMode: input.safetyMode,
    score: roundScore(weightedScore),
    criteria,
    eligibleForScheduling,
    blockingGates,
    rationale: buildRationale(input, eligibleForScheduling, blockingGates, roundScore(weightedScore))
  };
}

/**
 * Rank candidates deterministically. Schedulable targets rank above blocked
 * ones; within each group, higher score first, then targetId ascending so ties
 * are stable across runs and environments.
 */
export function rankTargetCandidates(inputs: TargetCandidateInput[]): TargetScorecard[] {
  return inputs
    .map(scoreTargetCandidate)
    .sort((a, b) => {
      if (a.eligibleForScheduling !== b.eligibleForScheduling) {
        return a.eligibleForScheduling ? -1 : 1;
      }
      if (b.score !== a.score) {
        return b.score - a.score;
      }
      return a.targetId.localeCompare(b.targetId);
    });
}

function evaluateConsumerValue(input: TargetCandidateInput): ScorecardCriterionResult {
  const named = typeof input.consumerValue.useCase === "string" && input.consumerValue.useCase.trim().length > 0;
  const score = named ? (input.consumerValue.reducesLiveCalls ? 1 : 0.6) : 0;
  return gate(
    "consumer_value",
    score,
    named,
    named
      ? input.consumerValue.reducesLiveCalls
        ? "Consumer owner named the use case and it reduces live provider calls."
        : "Consumer owner named the use case."
      : "No consumer owner has named a use case for this target."
  );
}

function evaluateSourceRights(input: TargetCandidateInput): ScorecardCriterionResult {
  const rights = input.sourceRights;
  const storable = rights.canStoreFacts && !rights.liveOnly;
  const passed = storable && rights.attributionPresent && rights.retentionDeclared;
  const score = passed ? 1 : storable && rights.attributionPresent ? 0.5 : 0;
  let reason: string;
  if (rights.liveOnly) {
    reason = "Source is live-only and cannot seed a durable cache.";
  } else if (!rights.canStoreFacts) {
    reason = "Source license does not permit storing facts.";
  } else if (!rights.attributionPresent) {
    reason = "Source attribution is missing.";
  } else if (!rights.retentionDeclared) {
    reason = "Source retention window is not declared.";
  } else {
    reason = "Source license, attribution, and retention checks pass.";
  }
  return gate("source_rights", score, passed, reason);
}

function evaluateTargetReadiness(input: TargetCandidateInput): ScorecardCriterionResult {
  const readiness = input.targetReadiness;
  const passed =
    readiness.schemaCompatible &&
    readiness.upsertKeysDeclared &&
    readiness.rlsPostureOk &&
    readiness.stagingEnvironmentExists;
  const satisfied = [
    readiness.schemaCompatible,
    readiness.upsertKeysDeclared,
    readiness.rlsPostureOk,
    readiness.stagingEnvironmentExists
  ].filter(Boolean).length;
  return gate(
    "target_readiness",
    satisfied / 4,
    passed,
    passed
      ? "Target schema, upsert keys, RLS posture, and staging environment are ready."
      : "Target schema, upsert keys, RLS posture, or staging environment is not ready."
  );
}

function evaluateDataQuality(input: TargetCandidateInput): ScorecardCriterionResult {
  const quality = input.dataQuality;
  const passed =
    quality.requiredFieldsPresent && quality.coordinatesValid && quality.sampleRowCount > 0;
  const score = passed ? Math.min(1, 0.6 + quality.sampleRowCount / 100) : 0;
  return gate(
    "data_quality",
    passed ? score : 0,
    passed,
    passed
      ? "Required fields, coordinates, and a non-empty sample pass quality gates."
      : "Required fields, coordinate validity, or sample volume failed quality gates."
  );
}

function evaluateCheckpointability(input: TargetCandidateInput): ScorecardCriterionResult {
  const passed = input.checkpointability.cursorStrategyDeclared;
  const score = passed ? (input.checkpointability.resumeTested ? 1 : 0.7) : 0;
  return gate(
    "checkpointability",
    score,
    passed,
    passed
      ? input.checkpointability.resumeTested
        ? "Cursor strategy declared and resume is tested."
        : "Cursor strategy declared; resume not yet tested."
      : "No durable cursor strategy is declared."
  );
}

function evaluateCostAndQuota(input: TargetCandidateInput): ScorecardCriterionResult {
  const cost = input.costAndQuota;
  const passed = cost.rowLimitDeclared && cost.stopConditionsDeclared && cost.withinBudget;
  const satisfied = [cost.rowLimitDeclared, cost.stopConditionsDeclared, cost.withinBudget].filter(
    Boolean
  ).length;
  return gate(
    "cost_and_quota",
    satisfied / 3,
    passed,
    passed
      ? "Row limit, stop conditions, and budget are declared and acceptable."
      : "Row limit, stop conditions, or budget is missing or exceeded."
  );
}

function evaluateCollisionRisk(input: TargetCandidateInput): ScorecardCriterionResult {
  const policy = input.collision.policy;
  const passed = policy !== "none";
  const score = policy === "block" ? 1 : policy === "review" ? 0.8 : policy === "auto" ? 0.6 : 0;
  return gate(
    "collision_risk",
    score,
    passed,
    passed
      ? `Collision policy is "${policy}".`
      : "No collision policy is declared (auto, review, or block required)."
  );
}

function evaluateBlastRadius(input: TargetCandidateInput): ScorecardCriterionResult {
  const blast = input.blastRadius;
  const passed = blast.bounded && blast.firstShipmentStagingOnly;
  const score = passed ? 1 : blast.bounded ? 0.5 : 0;
  return gate(
    "blast_radius",
    score,
    passed,
    passed
      ? "Run is bounded and the first shipment is staging-only."
      : "Run is unbounded or the first shipment is not staging-only."
  );
}

function evaluateObservability(input: TargetCandidateInput): ScorecardCriterionResult {
  const obs = input.observability;
  const passed =
    obs.eventsAvailable && obs.checkpointsAvailable && obs.deadLettersAvailable && obs.statsAvailable;
  const satisfied = [
    obs.eventsAvailable,
    obs.checkpointsAvailable,
    obs.deadLettersAvailable,
    obs.statsAvailable
  ].filter(Boolean).length;
  return gate(
    "observability",
    satisfied / 4,
    passed,
    passed
      ? "Events, checkpoints, dead letters, and stats are all observable."
      : "Dashboard cannot fully explain status, blockers, progress, and next action."
  );
}

function gate(
  criterion: TargetScoreCriterion,
  score: number,
  gatePassed: boolean,
  reason: string
): ScorecardCriterionResult {
  return {
    criterion,
    score: clamp01(score),
    weight: CRITERION_WEIGHTS[criterion],
    hardGate: true,
    gatePassed,
    reason
  };
}

function buildRationale(
  input: TargetCandidateInput,
  eligible: boolean,
  blockingGates: TargetScoreCriterion[],
  score: number
): string {
  if (eligible) {
    return `${input.targetId} scores ${score} and passes all selection gates; eligible for scheduling at ${input.safetyMode}.`;
  }
  return `${input.targetId} is blocked from scheduling by: ${blockingGates.join(", ")}.`;
}

function clamp01(value: number): number {
  if (Number.isNaN(value)) {
    return 0;
  }
  return Math.max(0, Math.min(1, value));
}

function roundScore(value: number): number {
  return Math.round(value * 10_000) / 10_000;
}
