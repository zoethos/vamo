/**
 * Schedule proposal policy — pure, deterministic planning.
 *
 * Implements the scheduling model in
 * docs/platform/ingestion/TARGET_SELECTION_AND_SCHEDULING.md §2/§4. A schedule
 * proposal is an explicit, reviewable work item produced *before* any task is
 * started. It is advisory: it requires operator approval and never starts a run
 * by itself.
 *
 * AI is advisory only. The AI rationale is represented as structured
 * input/output (`AiRationale`); this module derives a deterministic placeholder
 * rationale and does NOT call a live LLM. A real LLM adapter can later populate
 * the same shape behind an API boundary without changing this policy.
 *
 * Keep this module dependency-free (no node/pg/fs) so it is portable and
 * browser-safe.
 */

import type { TargetScorecard } from "./target-scorecard.js";

/** Progression tiers; production is never the default (see §2). */
export const TARGET_TIERS = [
  "candidate",
  "scout",
  "sample_dry_run",
  "staging_canary",
  "staging_expand",
  "production_candidate",
  "production_approved"
] as const;

export type TargetTier = (typeof TARGET_TIERS)[number];

export type SafetyMode = "dry_run" | "staging_write" | "production_write";

/**
 * Safety modes that IP-14 (first Vamo progressive dry run) must never emit.
 * Staging writes stay disabled for this slice; production writes are forbidden
 * outright until the shipment/approval slices exist.
 */
export const IP14_FORBIDDEN_SAFETY_MODES: readonly SafetyMode[] = [
  "staging_write",
  "production_write"
];

export interface ScheduleScope {
  geography: string;
  category: string;
  /** Hard upper bound on rows processed in this proposal. */
  rowLimit: number;
  sourcePartition?: string;
  boundingBox?: string;
}

export interface QuotaBudget {
  maxRows: number;
  maxSourceCalls: number;
  maxRuntimeSeconds: number;
  maxFailures: number;
}

export interface RunWindow {
  earliestStart: string;
  latestStop: string;
  quietHours?: string;
}

export interface StopConditions {
  maxPolicyBlockRate: number;
  maxDeadLetterRate: number;
  maxCollisionRate: number;
  stopOnSchemaMismatch: boolean;
  stopOnTargetWriteFailure: boolean;
  honorOperatorPause: boolean;
}

export type AiConfidence = "low" | "medium" | "high";

/** Structured, advisory AI rationale. Never a trusted durable fact. */
export interface AiRationale {
  /** Marks this as a non-LLM placeholder; a live adapter can replace it. */
  generator: "policy_advisory_placeholder";
  recommendedTier: TargetTier;
  confidence: AiConfidence;
  summary: string;
  evidence: string[];
  /** AI cannot bypass policy/approval; always advisory in this slice. */
  advisoryOnly: true;
}

export interface ApprovalRequirement {
  required: boolean;
  role: "ingestion_admin";
  requireMfa: boolean;
  requireAuditReason: boolean;
  /** What the operator is approving next, in plain language. */
  description: string;
}

export interface ScheduleProposal {
  projectKey: string;
  targetId: string;
  sourceId: string;
  tier: TargetTier;
  scope: ScheduleScope;
  batchSize: number;
  checkpointEveryRows: number;
  quotaBudget: QuotaBudget;
  runWindow: RunWindow;
  stopConditions: StopConditions;
  safetyMode: SafetyMode;
  aiRationale: AiRationale;
  approval: ApprovalRequirement;
}

export type ScheduleProposalErrorCode =
  | "target_not_eligible"
  | "production_write_forbidden"
  | "staging_write_disabled_for_slice"
  | "invalid_scope"
  | "invalid_tier_for_safety_mode";

export interface ScheduleProposalError {
  code: ScheduleProposalErrorCode;
  message: string;
}

export interface BuildScheduleProposalInput {
  scorecard: TargetScorecard;
  tier: TargetTier;
  safetyMode: SafetyMode;
  scope: ScheduleScope;
  batchSize: number;
  checkpointEveryRows: number;
  quotaBudget: QuotaBudget;
  runWindow: RunWindow;
  stopConditions: StopConditions;
  /** When true (IP-14), forbid staging and production writes. */
  forbidNonDryRun?: boolean;
}

export type BuildScheduleProposalResult =
  | { ok: true; proposal: ScheduleProposal; errors: [] }
  | { ok: false; errors: ScheduleProposalError[] };

/**
 * Build a bounded, deterministic schedule proposal. Returns structured errors
 * instead of throwing so the dashboard can explain exactly why a target cannot
 * be scheduled. The same input always yields the same proposal.
 */
export function buildScheduleProposal(
  input: BuildScheduleProposalInput
): BuildScheduleProposalResult {
  const errors: ScheduleProposalError[] = [];

  if (!input.scorecard.eligibleForScheduling) {
    errors.push({
      code: "target_not_eligible",
      message: `Target "${input.scorecard.targetId}" failed selection gates: ${input.scorecard.blockingGates.join(", ")}.`
    });
  }

  if (input.forbidNonDryRun && input.safetyMode === "production_write") {
    errors.push({
      code: "production_write_forbidden",
      message: "production_write is forbidden for this slice; production shipment is gated."
    });
  } else if (input.safetyMode === "production_write") {
    errors.push({
      code: "production_write_forbidden",
      message: "production_write requires the production shipment/approval slice, which is not enabled."
    });
  }

  if (input.forbidNonDryRun && input.safetyMode === "staging_write") {
    errors.push({
      code: "staging_write_disabled_for_slice",
      message: "staging_write is disabled for this slice; keep safety_mode at dry_run until staging canary approval."
    });
  }

  if (input.safetyMode !== "dry_run" && isDryRunTier(input.tier)) {
    errors.push({
      code: "invalid_tier_for_safety_mode",
      message: `Tier "${input.tier}" must run as dry_run, not "${input.safetyMode}".`
    });
  }

  if (input.scope.rowLimit <= 0) {
    errors.push({
      code: "invalid_scope",
      message: "Scope rowLimit must be a positive bound."
    });
  }
  if (input.scope.geography.trim().length === 0 || input.scope.category.trim().length === 0) {
    errors.push({
      code: "invalid_scope",
      message: "Scope must declare a geography and category to bound blast radius."
    });
  }

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  return {
    ok: true,
    errors: [],
    proposal: {
      projectKey: input.scorecard.projectKey,
      targetId: input.scorecard.targetId,
      sourceId: input.scorecard.sourceId,
      tier: input.tier,
      scope: { ...input.scope },
      batchSize: input.batchSize,
      checkpointEveryRows: input.checkpointEveryRows,
      quotaBudget: { ...input.quotaBudget },
      runWindow: { ...input.runWindow },
      stopConditions: { ...input.stopConditions },
      safetyMode: input.safetyMode,
      aiRationale: deriveAdvisoryRationale(input.scorecard, input.tier),
      approval: deriveApproval(input.safetyMode)
    }
  };
}

/**
 * Derive a structured, advisory rationale from the scorecard. Deterministic and
 * LLM-free: confidence and evidence come from the scorecard, not a model call.
 */
export function deriveAdvisoryRationale(
  scorecard: TargetScorecard,
  recommendedTier: TargetTier
): AiRationale {
  const passedGates = scorecard.criteria.filter((criterion) => criterion.gatePassed).length;
  const totalGates = scorecard.criteria.length;
  const confidence: AiConfidence = !scorecard.eligibleForScheduling
    ? "low"
    : scorecard.score >= 0.85
      ? "high"
      : scorecard.score >= 0.6
        ? "medium"
        : "low";

  const evidence = scorecard.criteria
    .slice()
    .sort((a, b) => b.weight - a.weight || a.criterion.localeCompare(b.criterion))
    .map((criterion) => `${criterion.criterion}: ${criterion.reason}`);

  return {
    generator: "policy_advisory_placeholder",
    recommendedTier,
    confidence,
    summary: scorecard.eligibleForScheduling
      ? `Advisory: ${scorecard.targetId} passes ${passedGates}/${totalGates} gates (score ${scorecard.score}); recommend running at ${recommendedTier}.`
      : `Advisory: ${scorecard.targetId} is not schedulable; ${totalGates - passedGates}/${totalGates} gates failed.`,
    evidence,
    advisoryOnly: true
  };
}

function deriveApproval(safetyMode: SafetyMode): ApprovalRequirement {
  if (safetyMode === "dry_run") {
    return {
      required: true,
      role: "ingestion_admin",
      requireMfa: true,
      requireAuditReason: true,
      description:
        "Admin (MFA + audit reason) must approve before promoting this dry run to a staging canary."
    };
  }
  return {
    required: true,
    role: "ingestion_admin",
    requireMfa: true,
    requireAuditReason: true,
    description:
      "Admin (MFA + audit reason) must approve before any staging or production write."
  };
}

function isDryRunTier(tier: TargetTier): boolean {
  return tier === "candidate" || tier === "scout" || tier === "sample_dry_run";
}
