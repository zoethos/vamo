/**
 * Build a minimal ProgressiveRunReport from batch dry-run evidence for IP-18.6.3
 * package assembly. Reuses IP-17 buildProductionInboxPackage without a second
 * package format.
 */

import type { ProductionPackageDryRunEvidence } from "./batch-production-package-wave-policy.js";
import type { ProgressiveRunReport } from "./progressive-run.js";

export function buildBatchUnitProgressiveRunReport(input: {
  projectKey: string;
  targetKey: string;
  sourceKey: string;
  dryRunEvidence: ProductionPackageDryRunEvidence;
}): ProgressiveRunReport {
  const insert = input.dryRunEvidence.insertCount;
  const update = input.dryRunEvidence.updateCount;
  const total = insert + update;
  const checkpointValue =
    typeof input.dryRunEvidence.rowsProcessed === "number"
      ? input.dryRunEvidence.rowsProcessed
      : total;

  return {
    projectKey: input.projectKey,
    targetId: input.targetKey,
    sourceId: input.sourceKey,
    tier: "sample_dry_run",
    safetyMode: "dry_run",
    stages: [
      {
        stage: "sample_dry_run",
        status: "passed",
        detail: `Batch dry-run diff: ${insert} insert, ${update} update (no target writes).`,
        signal: "batch_dry_run_diff_ready"
      },
      {
        stage: "review_required",
        status: "review_required",
        detail: "Production package-wave approval recorded.",
        signal: "review_required"
      }
    ],
    currentStage: "review_required",
    preflight: { passed: true, checks: [], failures: [] },
    scout: {
      sampleRowCount: checkpointValue,
      candidateCount: total,
      deadLetterCount: 0,
      policyBlockCount: 0,
      detail: "Batch dry-run evidence from control-plane queue item."
    },
    rowCounts: {
      read: checkpointValue,
      staged: total,
      policyBlocked: 0,
      deadLettered: 0
    },
    shipmentDiff: {
      compatible: true,
      insert,
      update,
      noOp: 0,
      delete: input.dryRunEvidence.deleteCount ?? 0,
      total,
      incompatibilities: 0
    },
    checkpoint: {
      cursorScope: input.dryRunEvidence.executionKey ?? "batch_dry_run",
      cursorValue: checkpointValue,
      lastRecordKey: input.dryRunEvidence.executionKey ?? "batch_dry_run",
      processedCount: checkpointValue
    },
    policyBlocks: [],
    deadLetters: [],
    wroteToTarget: false,
    reachedReview: true,
    aiRationale: {
      generator: "policy_advisory_placeholder",
      recommendedTier: "sample_dry_run",
      confidence: "high",
      summary: "Batch package-wave delivery uses persisted dry-run evidence.",
      evidence: ["batch_dry_run_evidence"],
      advisoryOnly: true
    },
    nextApproval: {
      required: true,
      role: "ingestion_admin",
      requireMfa: true,
      requireAuditReason: true,
      description:
        "Confirmation-gated production inbox delivery requires explicit operator confirmation."
    }
  };
}
