/**
 * Progressive run stages — orchestration policy for the first Vamo dry run.
 *
 * Implements the progressive run stages in
 * docs/platform/ingestion/TARGET_SELECTION_AND_SCHEDULING.md §5, bounded to the
 * IP-14 slice:
 *
 *   preflight -> scout -> sample_dry_run -> review_required
 *
 * No staging or production write happens in this slice. The orchestrator refuses
 * to run unless the proposal's safety mode is `dry_run`, and the dry-run planner
 * is injected (dependency injection) so this module stays pure: it imports no
 * source/target adapter at runtime and therefore creates no package cycle. The
 * actual source read and target dry-run diff flow through the already-proven
 * adapter interfaces supplied by the caller.
 */

import type { PipelineRunResult, RunFixturePipelineInput, StagedCandidate } from "./pipeline-runner.js";
import type { ScheduleProposal } from "./schedule-proposal.js";
import type { ShipmentPlan } from "./shipment-plan.js";
import type { TargetScorecard } from "./target-scorecard.js";
import type { PipelineSpec, TargetProjectSpec } from "../../spec/src/types.js";

export const PROGRESSIVE_STAGES = [
  "preflight",
  "scout",
  "sample_dry_run",
  "review_required"
] as const;

export type ProgressiveStage = (typeof PROGRESSIVE_STAGES)[number];

export type StageStatus = "passed" | "blocked" | "skipped" | "review_required";

export interface StageResult {
  stage: ProgressiveStage;
  status: StageStatus;
  detail: string;
  /** Stable signal string for events/telemetry. */
  signal: string;
}

export interface PreflightCheck {
  id: string;
  passed: boolean;
  detail: string;
}

export interface PreflightReport {
  passed: boolean;
  checks: PreflightCheck[];
  failures: string[];
}

export interface ScoutReport {
  sampleRowCount: number;
  candidateCount: number;
  deadLetterCount: number;
  policyBlockCount: number;
  detail: string;
}

export interface ShipmentDiffSummary {
  compatible: boolean;
  insert: number;
  update: number;
  noOp: number;
  delete: number;
  total: number;
  incompatibilities: number;
}

export interface CheckpointReport {
  cursorScope: string;
  cursorValue: string | number | null;
  lastRecordKey: string | null;
  processedCount: number;
}

export interface RowCounts {
  read: number;
  staged: number;
  policyBlocked: number;
  deadLettered: number;
}

export interface ProgressiveRunReport {
  projectKey: string;
  targetId: string;
  sourceId: string;
  tier: ScheduleProposal["tier"];
  safetyMode: ScheduleProposal["safetyMode"];
  stages: StageResult[];
  currentStage: ProgressiveStage;
  preflight: PreflightReport;
  scout: ScoutReport;
  rowCounts: RowCounts;
  shipmentDiff: ShipmentDiffSummary;
  checkpoint: CheckpointReport;
  policyBlocks: string[];
  deadLetters: string[];
  /** True only when no write of any kind occurred. */
  wroteToTarget: false;
  nextApproval: ScheduleProposal["approval"];
}

export interface DryRunPlanRequest {
  target: TargetProjectSpec;
  candidates: StagedCandidate[];
}

/** Injected adapter boundary; keeps this module free of adapter imports. */
export interface ProgressiveDryRunDeps {
  runPipeline(input: RunFixturePipelineInput): Promise<PipelineRunResult>;
  planDryRun(request: DryRunPlanRequest): Promise<ShipmentPlan>;
}

export interface RunProgressiveDryRunInput {
  proposal: ScheduleProposal;
  scorecard: TargetScorecard;
  pipeline: PipelineSpec;
  target: TargetProjectSpec;
  fixtureRoot: string;
}

/** Pure preflight: specs parsed, source rights, target readiness, keys. */
export function evaluatePreflight(input: {
  scorecard: TargetScorecard;
  pipeline: PipelineSpec;
  target: TargetProjectSpec;
}): PreflightReport {
  const { pipeline, target, scorecard } = input;
  const upsertKeysDeclared = target.shipment.tables.every(
    (table) => table.upsertKeys.length > 0
  );
  const hasAttributionGate = pipeline.qualityGates.some(
    (gate) => gate.type === "attribution_present"
  );

  const checks: PreflightCheck[] = [
    {
      id: "spec_valid",
      passed: pipeline.kind === "ingestion.pipeline" && target.kind === "ingestion.target",
      detail: "Pipeline and target specs parsed and validated by the spec kernel."
    },
    {
      id: "source_rights",
      passed: pipeline.source.license.canStoreFacts && !pipeline.source.license.liveOnly,
      detail: "Source license permits storing facts and is not live-only."
    },
    {
      id: "attribution",
      passed: pipeline.source.license.attribution.trim().length > 0 && hasAttributionGate,
      detail: "Source attribution is present and enforced by a quality gate."
    },
    {
      id: "target_schema_ready",
      passed: target.shipment.tables.length > 0,
      detail: "Target declares at least one shipment table."
    },
    {
      id: "upsert_keys",
      passed: upsertKeysDeclared,
      detail: "Every target table declares upsert keys."
    },
    {
      id: "rls_posture",
      passed: target.security.requireRlsOnExposedSchemas,
      detail: "Target requires RLS on exposed schemas."
    },
    {
      id: "dry_run_only",
      passed: target.security.writeMode === "dry_run" && target.shipment.defaultMode === "dry_run",
      detail: "Target write mode and default shipment mode are dry_run."
    },
    {
      id: "selection_gates",
      passed: scorecard.eligibleForScheduling,
      detail: "Target passes all selection scorecard gates."
    }
  ];

  const failures = checks.filter((check) => !check.passed).map((check) => check.id);
  return {
    passed: failures.length === 0,
    checks,
    failures
  };
}

export function buildScoutReport(run: PipelineRunResult, sampleRowCount: number): ScoutReport {
  const policyBlockCount = run.events.filter((event) => event.eventType === "policy_blocked").length;
  return {
    sampleRowCount,
    candidateCount: run.candidates.length,
    deadLetterCount: run.deadLetters.length,
    policyBlockCount,
    detail: `Scouted ${sampleRowCount} sample rows: ${run.candidates.length} staged, ${run.deadLetters.length} dead-lettered, ${policyBlockCount} policy-blocked.`
  };
}

export function summarizeShipmentDiff(plan: ShipmentPlan): ShipmentDiffSummary {
  const counts = { insert: 0, update: 0, no_op: 0, delete: 0 };
  for (const item of plan.items) {
    counts[item.operation] += 1;
  }
  return {
    compatible: plan.compatible,
    insert: counts.insert,
    update: counts.update,
    noOp: counts.no_op,
    delete: counts.delete,
    total: plan.items.length,
    incompatibilities: plan.incompatibilities.length
  };
}

/**
 * Orchestrate the bounded progressive dry run. Refuses any non-dry-run safety
 * mode so a misconfigured proposal can never reach the (injected) planner with
 * intent to write. The planner itself is a dry run and writes nothing.
 */
export async function runProgressiveDryRun(
  input: RunProgressiveDryRunInput,
  deps: ProgressiveDryRunDeps
): Promise<ProgressiveRunReport> {
  if (input.proposal.safetyMode !== "dry_run") {
    throw new Error(
      `runProgressiveDryRun refuses safety mode "${input.proposal.safetyMode}"; IP-14 is dry_run only.`
    );
  }
  if (input.target.security.writeMode !== "dry_run") {
    throw new Error("Target write mode must be dry_run for the IP-14 progressive dry run.");
  }

  const stages: StageResult[] = [];

  const preflight = evaluatePreflight({
    scorecard: input.scorecard,
    pipeline: input.pipeline,
    target: input.target
  });
  stages.push({
    stage: "preflight",
    status: preflight.passed ? "passed" : "blocked",
    detail: preflight.passed
      ? "Preflight passed: specs, rights, attribution, schema, keys, RLS, dry-run posture."
      : `Preflight blocked: ${preflight.failures.join(", ")}.`,
    signal: preflight.passed ? "preflight_passed" : "preflight_blocked"
  });

  if (!preflight.passed) {
    return assembleReport(input, stages, preflight, emptyScout(), emptyDiff(), emptyCheckpoint(), [], []);
  }

  // Scout: read a tiny bounded sample, then stop.
  const scoutBatch = Math.min(input.proposal.batchSize, input.proposal.scope.rowLimit);
  const scoutRun = await deps.runPipeline({
    pipeline: input.pipeline,
    batchSize: scoutBatch,
    fixtureRoot: input.fixtureRoot
  });
  const scout = buildScoutReport(scoutRun, scoutRun.checkpoint.processedCount);
  stages.push({
    stage: "scout",
    status: "passed",
    detail: scout.detail,
    signal: "scout_sampled"
  });

  // Sample dry run: process the bounded slice and produce a shipment diff.
  const sampleRun = await deps.runPipeline({
    pipeline: input.pipeline,
    batchSize: input.proposal.scope.rowLimit,
    fixtureRoot: input.fixtureRoot
  });
  const plan = await deps.planDryRun({
    target: input.target,
    candidates: sampleRun.candidates
  });
  const shipmentDiff = summarizeShipmentDiff(plan);
  stages.push({
    stage: "sample_dry_run",
    status: shipmentDiff.compatible ? "passed" : "blocked",
    detail: shipmentDiff.compatible
      ? `Dry-run diff: ${shipmentDiff.insert} insert, ${shipmentDiff.update} update, ${shipmentDiff.noOp} no-op (no target writes).`
      : `Dry-run diff incompatible: ${shipmentDiff.incompatibilities} schema/keys issue(s).`,
    signal: shipmentDiff.compatible ? "sample_dry_run_diff_ready" : "sample_dry_run_incompatible"
  });

  const policyBlocks = sampleRun.events
    .filter((event) => event.eventType === "policy_blocked")
    .map((event) => `${event.signal ?? "policy_blocked"}: ${event.message}`);
  const deadLetters = sampleRun.deadLetters.map(
    (deadLetter) => `${deadLetter.reasonCode}: ${deadLetter.reasonMessage}`
  );

  const checkpoint: CheckpointReport = {
    cursorScope: sampleRun.checkpoint.cursorScope,
    cursorValue: sampleRun.checkpoint.cursorValue.last ?? null,
    lastRecordKey: sampleRun.checkpoint.lastRecordKey ?? null,
    processedCount: sampleRun.checkpoint.processedCount
  };

  stages.push({
    stage: "review_required",
    status: "review_required",
    detail:
      "Dry run complete. Operator review required before any staging canary; no write occurred.",
    signal: "review_required"
  });

  return assembleReport(
    input,
    stages,
    preflight,
    scout,
    shipmentDiff,
    checkpoint,
    policyBlocks,
    deadLetters,
    sampleRun
  );
}

function assembleReport(
  input: RunProgressiveDryRunInput,
  stages: StageResult[],
  preflight: PreflightReport,
  scout: ScoutReport,
  shipmentDiff: ShipmentDiffSummary,
  checkpoint: CheckpointReport,
  policyBlocks: string[],
  deadLetters: string[],
  sampleRun?: PipelineRunResult
): ProgressiveRunReport {
  const currentStage = stages[stages.length - 1]?.stage ?? "preflight";
  const rowCounts: RowCounts = {
    read: sampleRun?.checkpoint.processedCount ?? 0,
    staged: sampleRun?.candidates.length ?? 0,
    policyBlocked: policyBlocks.length,
    deadLettered: deadLetters.length
  };

  return {
    projectKey: input.proposal.projectKey,
    targetId: input.proposal.targetId,
    sourceId: input.proposal.sourceId,
    tier: input.proposal.tier,
    safetyMode: input.proposal.safetyMode,
    stages,
    currentStage,
    preflight,
    scout,
    rowCounts,
    shipmentDiff,
    checkpoint,
    policyBlocks,
    deadLetters,
    wroteToTarget: false,
    nextApproval: input.proposal.approval
  };
}

function emptyScout(): ScoutReport {
  return {
    sampleRowCount: 0,
    candidateCount: 0,
    deadLetterCount: 0,
    policyBlockCount: 0,
    detail: "Scout skipped because preflight blocked the run."
  };
}

function emptyDiff(): ShipmentDiffSummary {
  return { compatible: false, insert: 0, update: 0, noOp: 0, delete: 0, total: 0, incompatibilities: 0 };
}

function emptyCheckpoint(): CheckpointReport {
  return { cursorScope: "none", cursorValue: null, lastRecordKey: null, processedCount: 0 };
}
