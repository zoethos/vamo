/**
 * Progressive run dashboard read model — pure transform.
 *
 * Turns target scorecards, schedule proposals, and progressive-run reports into
 * the operator-console view required by
 * docs/platform/ingestion/TARGET_SELECTION_AND_SCHEDULING.md §6: proposed /
 * scheduled / running / review-required work, target score and AI rationale,
 * current tier, checkpoint, row counts, policy blocks, dead letters, and the
 * exact next approval.
 *
 * The UI consumes only this view; it never reads control tables or runs policy.
 * Keep this module dependency-free (no node/pg/fs) so the Next bundle stays
 * clean and browser-safe.
 */

import {
  buildScheduleProposal,
  deriveAdvisoryRationale,
  type AiConfidence,
  type SafetyMode,
  type ScheduleProposal,
  type TargetTier
} from "./schedule-proposal.js";
import type { ProgressiveRunReport, ProgressiveStage } from "./progressive-run.js";
import {
  scoreTargetCandidate,
  type TargetCandidateInput,
  type TargetScorecard
} from "./target-scorecard.js";

export type ProgressiveWorkStatus =
  | "proposed"
  | "scheduled"
  | "running"
  | "review_required"
  | "blocked";

export type CanaryShipmentStatus =
  | "planned"
  | "dry_run"
  | "approved"
  | "shipping"
  | "succeeded"
  | "failed"
  | "cancelled";

/**
 * Latest staging-canary shipment ledger row for a target, as surfaced to the
 * dashboard. Read-only projection of `ingestion_platform.ingestion_shipments`.
 */
export interface CanaryShipmentState {
  status: CanaryShipmentStatus;
  mode: string;
  shipmentKey: string;
  createdAt: string;
  approvalAuditId?: string;
}

/**
 * Statuses that mean the canary slot for a reviewed proposal is already spent:
 * a shipment has been approved, is shipping, or has succeeded. Treat any of
 * these as "already shipped" so the dashboard does not invite a repeat approval
 * against the same `review_required` row.
 */
export const ACTIVE_CANARY_SHIPMENT_STATUSES: readonly CanaryShipmentStatus[] = [
  "approved",
  "shipping",
  "succeeded"
];

export function isActiveCanaryShipment(shipment?: CanaryShipmentState | null): boolean {
  return Boolean(shipment) && ACTIVE_CANARY_SHIPMENT_STATUSES.includes(shipment!.status);
}

export interface ProgressiveBacklogEntryInput {
  workStatus: ProgressiveWorkStatus;
  scorecard: TargetScorecard;
  tier: TargetTier;
  safetyMode: SafetyMode;
  canaryBounds?: ReviewedCanaryBounds;
  scheduledApprovalDescription?: string;
  report?: ProgressiveRunReport;
  /** Latest staging-canary shipment for this target, if any exists. */
  canaryShipment?: CanaryShipmentState | null;
}

export interface ProgressiveRunSnapshot {
  entries: ProgressiveBacklogEntryInput[];
}

export interface ReviewedCanaryBounds {
  geography: string;
  category: string;
  /** Exact reviewed write count, not an operator-entered upper bound. */
  maxRows: number;
}

export interface ProgressiveTone {
  tone: "good" | "watch" | "danger" | "neutral";
}

export interface ProgressiveBacklogRow extends ProgressiveTone {
  targetId: string;
  projectKey: string;
  sourceId: string;
  workStatus: ProgressiveWorkStatus;
  tier: TargetTier;
  safetyMode: SafetyMode;
  score: number;
  eligible: boolean;
  /** Scorecard rationale: why the target is (not) schedulable. */
  rationale: string;
  /** Advisory, deterministic AI rationale (placeholder, never a live LLM). */
  aiSummary: string;
  aiConfidence: AiConfidence;
  aiRecommendedTier: TargetTier;
  /** Current progressive stage when a run report exists. */
  stage: ProgressiveStage | "not_started";
  checkpoint: string;
  rowsRead: number;
  rowsStaged: number;
  policyBlockCount: number;
  deadLetterCount: number;
  /** Dry-run invariant surfaced to the console: a run never wrote to its target. */
  wroteToTarget: boolean;
  /** Reviewed, immutable bounds for a staging-canary approval. */
  canaryBounds?: ReviewedCanaryBounds;
  /** Latest staging-canary shipment ledger row for this target, if any. */
  canaryShipment?: CanaryShipmentState;
  /**
   * True when an active/spent canary shipment exists (approved, shipping, or
   * succeeded). The dashboard must not offer a repeat approval in this state.
   */
  canaryShipped: boolean;
  blockers: string[];
  policyBlocks: string[];
  deadLetters: string[];
  shipmentDiff: string;
  nextApproval: string;
}

export interface ProgressiveRunView {
  rows: ProgressiveBacklogRow[];
  /** Counts by work status for the backlog summary. */
  summary: {
    proposed: number;
    scheduled: number;
    running: number;
    reviewRequired: number;
    blocked: number;
  };
  /** The single answer to "what needs an operator decision next?". */
  nextAction: string;
}

const WORK_STATUS_TONE: Record<ProgressiveWorkStatus, ProgressiveTone["tone"]> = {
  proposed: "neutral",
  scheduled: "neutral",
  running: "good",
  review_required: "watch",
  blocked: "danger"
};

export function buildProgressiveRunView(snapshot: ProgressiveRunSnapshot): ProgressiveRunView {
  const rows = snapshot.entries.map(toRow);
  const summary = {
    proposed: count(rows, "proposed"),
    scheduled: count(rows, "scheduled"),
    running: count(rows, "running"),
    reviewRequired: count(rows, "review_required"),
    blocked: count(rows, "blocked")
  };

  return {
    rows,
    summary,
    nextAction: deriveNextAction(rows)
  };
}

function toRow(entry: ProgressiveBacklogEntryInput): ProgressiveBacklogRow {
  const { scorecard, report } = entry;
  const shipment = report?.shipmentDiff;
  const canaryShipment = entry.canaryShipment ?? undefined;
  const canaryShipped = isActiveCanaryShipment(canaryShipment);
  // Prefer the rationale carried by an executed run; otherwise derive the same
  // deterministic advisory rationale the proposal would use for this tier.
  const aiRationale = report?.aiRationale ?? deriveAdvisoryRationale(scorecard, entry.tier);
  return {
    targetId: scorecard.targetId,
    projectKey: scorecard.projectKey,
    sourceId: scorecard.sourceId,
    workStatus: entry.workStatus,
    tier: entry.tier,
    safetyMode: entry.safetyMode,
    score: scorecard.score,
    eligible: scorecard.eligibleForScheduling,
    rationale: scorecard.rationale,
    aiSummary: aiRationale.summary,
    aiConfidence: aiRationale.confidence,
    aiRecommendedTier: aiRationale.recommendedTier,
    stage: report?.currentStage ?? "not_started",
    checkpoint: report
      ? `${report.checkpoint.cursorScope}=${report.checkpoint.cursorValue ?? "none"} (n=${report.checkpoint.processedCount})`
      : "none",
    rowsRead: report?.rowCounts.read ?? 0,
    rowsStaged: report?.rowCounts.staged ?? 0,
    policyBlockCount: report?.rowCounts.policyBlocked ?? 0,
    deadLetterCount: report?.rowCounts.deadLettered ?? 0,
    wroteToTarget: report?.wroteToTarget ?? false,
    canaryBounds: entry.canaryBounds,
    canaryShipment,
    canaryShipped,
    blockers: scorecard.blockingGates.slice(),
    policyBlocks: report?.policyBlocks.slice() ?? [],
    deadLetters: report?.deadLetters.slice() ?? [],
    shipmentDiff: shipment
      ? `${shipment.insert} insert / ${shipment.update} update / ${shipment.noOp} no-op${shipment.compatible ? "" : " (incompatible)"}`
      : "not planned",
    // A spent canary takes precedence over the policy approval prompt: the
    // ledger is the source of truth, even when the proposal row still reads
    // review_required.
    nextApproval: canaryShipped
      ? describeShippedCanary(canaryShipment)
      : report?.nextApproval.description ?? entry.scheduledApprovalDescription ?? "Awaiting scorecard review.",
    tone: WORK_STATUS_TONE[entry.workStatus]
  };
}

function describeShippedCanary(shipment?: CanaryShipmentState): string {
  if (!shipment) {
    return "Already shipped to Vamo staging.";
  }
  const approval = shipment.approvalAuditId ? ` (approval ${shipment.approvalAuditId})` : "";
  return `Already shipped to Vamo staging${approval}; create a new proposal/run to ship again.`;
}

export function deriveReviewedCanaryBounds(input: {
  proposal?: ScheduleProposal | null;
  report?: ProgressiveRunReport | null;
}): ReviewedCanaryBounds | undefined {
  const geography = input.proposal?.scope.geography?.trim();
  const category = input.proposal?.scope.category?.trim();
  const diff = input.report?.shipmentDiff;
  const maxRows = diff ? diff.insert + diff.update : 0;

  if (!geography || !category || maxRows <= 0) {
    return undefined;
  }

  return { geography, category, maxRows };
}

function count(rows: ProgressiveBacklogRow[], status: ProgressiveWorkStatus): number {
  return rows.filter((row) => row.workStatus === status).length;
}

function deriveNextAction(rows: ProgressiveBacklogRow[]): string {
  // A review_required row whose canary already shipped is not actionable: the
  // ledger has spent the canary slot. Only an unshipped review needs a decision.
  const review = rows.find((row) => row.workStatus === "review_required" && !row.canaryShipped);
  if (review) {
    return `Review ${review.targetId}: ${review.nextApproval}`;
  }
  const shipped = rows.find((row) => row.workStatus === "review_required" && row.canaryShipped);
  if (shipped) {
    return `${shipped.targetId} already shipped to Vamo staging${
      shipped.canaryShipment?.shipmentKey ? ` (${shipped.canaryShipment.shipmentKey})` : ""
    }; create a new proposal/run to ship again.`;
  }
  const running = rows.find((row) => row.workStatus === "running");
  if (running) {
    return `Monitor ${running.targetId} at stage ${running.stage}.`;
  }
  const scheduled = rows.find((row) => row.workStatus === "scheduled");
  if (scheduled) {
    return `Start scheduled dry run for ${scheduled.targetId}.`;
  }
  const proposed = rows.find((row) => row.workStatus === "proposed" && row.eligible);
  if (proposed) {
    return `Approve scheduling for proposed target ${proposed.targetId}.`;
  }
  return "No eligible work; resolve blocked targets before scheduling.";
}

/* ----------------------------- Sample data ------------------------------- */
/* A representative IP-14 snapshot so the admin shell renders the progressive
   board before a live control API exists. Built from the same pure policy the
   platform enforces, so the sample cannot drift from real behavior. */

const sampleVamoCandidate: TargetCandidateInput = {
  targetId: "vamo-place-intelligence-staging",
  projectKey: "vamo",
  sourceId: "fsq-os-places-sample",
  safetyMode: "dry_run",
  consumerValue: {
    useCase: "Seed Vamo place cache to cut live Places calls on trip creation.",
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

const sampleGoogleCandidate: TargetCandidateInput = {
  targetId: "google-live-rehearsal",
  projectKey: "vamo",
  sourceId: "google-places-live",
  safetyMode: "dry_run",
  consumerValue: { useCase: "Live visual validation only.", reducesLiveCalls: false },
  sourceRights: {
    canStoreFacts: false,
    attributionPresent: true,
    retentionDeclared: false,
    liveOnly: true
  },
  targetReadiness: {
    schemaCompatible: true,
    upsertKeysDeclared: true,
    rlsPostureOk: true,
    stagingEnvironmentExists: true
  },
  dataQuality: { requiredFieldsPresent: true, coordinatesValid: true, sampleRowCount: 1 },
  checkpointability: { cursorStrategyDeclared: false, resumeTested: false },
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

const sampleVamoScorecard = scoreTargetCandidate(sampleVamoCandidate);
const sampleGoogleScorecard = scoreTargetCandidate(sampleGoogleCandidate);

const sampleReport: ProgressiveRunReport = {
  projectKey: "vamo",
  targetId: "vamo-place-intelligence-staging",
  sourceId: "fsq-os-places-sample",
  tier: "sample_dry_run",
  safetyMode: "dry_run",
  stages: [
    { stage: "preflight", status: "passed", detail: "Preflight passed.", signal: "preflight_passed" },
    { stage: "scout", status: "passed", detail: "Scouted 3 rows.", signal: "scout_sampled" },
    {
      // 1 in-scope staged candidate x 2 target tables = 2 insert operations.
      stage: "sample_dry_run",
      status: "passed",
      detail: "Dry-run diff: 2 insert, 0 update, 0 no-op (no target writes).",
      signal: "sample_dry_run_diff_ready"
    },
    {
      stage: "review_required",
      status: "review_required",
      detail: "Operator review required before staging canary.",
      signal: "review_required"
    }
  ],
  currentStage: "review_required",
  preflight: { passed: true, checks: [], failures: [] },
  scout: {
    // Preview of the first 3 rows: 1 in-scope staged, 1 dead-lettered (missing name).
    sampleRowCount: 3,
    candidateCount: 1,
    deadLetterCount: 1,
    policyBlockCount: 0,
    detail: "Scouted 3 sample rows (preview): 1 staged, 1 dead-lettered, 0 policy-blocked."
  },
  // Full bounded sample (5 rows): 1 staged in-scope, row 4 media policy-blocked,
  // rows 2/5 excluded by scope, row 3 missing name emits 2 mapping dead letters.
  rowCounts: { read: 5, staged: 1, policyBlocked: 3, deadLettered: 2 },
  shipmentDiff: {
    compatible: true,
    insert: 2,
    update: 0,
    noOp: 0,
    delete: 0,
    total: 2,
    incompatibilities: 0
  },
  checkpoint: {
    cursorScope: "source_row_id",
    cursorValue: 5,
    lastRecordKey: "fsq_sagrada_familia",
    processedCount: 5
  },
  policyBlocks: [
    "source.storage_rights: media bytes blocked by policy",
    "scope_mismatch: fsq_eiffel_tower outside rome-italy/poi",
    "scope_mismatch: fsq_sagrada_familia outside rome-italy/poi"
  ],
  deadLetters: [
    'missing_mapped_field: Required mapping source "source.name" is missing.',
    'missing_mapped_field: Required mapping source "source.name" is missing.'
  ],
  wroteToTarget: false,
  reachedReview: true,
  aiRationale: deriveAdvisoryRationale(sampleVamoScorecard, "sample_dry_run"),
  nextApproval: {
    required: true,
    role: "ingestion_admin",
    requireMfa: true,
    requireAuditReason: true,
    description:
      "Admin (MFA + audit reason) must approve before promoting this dry run to a staging canary."
  }
};

export const sampleProgressiveRunSnapshot: ProgressiveRunSnapshot = {
  entries: [
    {
      workStatus: "review_required",
      scorecard: sampleVamoScorecard,
      tier: "sample_dry_run",
      safetyMode: "dry_run",
      canaryBounds: { geography: "rome-italy", category: "poi", maxRows: 2 },
      report: sampleReport
    },
    {
      workStatus: "blocked",
      scorecard: sampleGoogleScorecard,
      tier: "candidate",
      safetyMode: "dry_run",
      scheduledApprovalDescription:
        "Blocked: live-only source cannot seed a durable cache; no scheduling path."
    }
  ]
};

/** Convenience for the sample proposal shown beside the board. */
export function sampleVamoProposal() {
  return buildScheduleProposal({
    scorecard: sampleVamoScorecard,
    tier: "sample_dry_run",
    safetyMode: "dry_run",
    scope: { geography: "rome-italy", category: "poi", rowLimit: 3 },
    batchSize: 2,
    checkpointEveryRows: 2,
    quotaBudget: { maxRows: 3, maxSourceCalls: 1, maxRuntimeSeconds: 30, maxFailures: 1 },
    runWindow: { earliestStart: "2026-06-28T00:00:00Z", latestStop: "2026-06-28T23:59:59Z" },
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
}
