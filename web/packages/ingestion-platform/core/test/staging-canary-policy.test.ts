import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { AdminPrincipal } from "../src/admin-auth.js";
import type { ProgressiveRunReport, ShipmentDiffSummary } from "../src/progressive-run.js";
import {
  evaluateStagingCanaryPromotion,
  STAGING_CANARY_MAX_ROWS,
  type EvaluateStagingCanaryPromotionInput,
  type StagingCanaryBlockCode
} from "../src/staging-canary-policy.js";

const NOW = "2026-06-28T10:00:00.000Z";
const FRESH = "2026-06-28T09:58:00.000Z"; // 2 min ago
const STALE = "2026-06-28T09:00:00.000Z"; // 1 hour ago

describe("evaluateStagingCanaryPromotion", () => {
  it("accepts a reviewed, bounded, admin+AAL2+reason promotion", () => {
    const result = evaluateStagingCanaryPromotion(validInput());
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.plan.safetyMode, "staging_write");
    assert.equal(result.plan.shipmentMode, "approved_write");
    assert.equal(result.plan.environment, "staging");
    assert.equal(result.plan.write.writeCount, 3);
    assert.equal(result.plan.auditReason, "first Rome landmark canary");
    assert.equal(result.plan.approvedBy.role, "admin");
    assert.equal(result.plan.bounds.maxRows, STAGING_CANARY_MAX_ROWS);
  });

  it("blocks production_write outright", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.transition.to = "production_write";
        input.targetEnvironment = "production";
      })
    );
    assertBlocked(result, "production_write_forbidden");
    assertBlocked(result, "not_staging_environment");
  });

  it("blocks a non-staging environment", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.targetEnvironment = "production";
      })
    );
    assertBlocked(result, "not_staging_environment");
  });

  it("blocks when the run never reached review", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.runReport.reachedReview = false;
      })
    );
    assertBlocked(result, "run_not_reviewed");
  });

  it("blocks an incompatible reviewed diff", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.runReport.shipmentDiff.compatible = false;
        input.runReport.shipmentDiff.incompatibilities = 2;
      })
    );
    assertBlocked(result, "diff_incompatible");
  });

  it("blocks a non-admin principal", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.approval.principal.role = "operator";
      })
    );
    assertBlocked(result, "role_denied");
  });

  it("blocks a principal lacking project scope", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.approval.principal.scopes = ["other-project"];
      })
    );
    assertBlocked(result, "scope_denied");
  });

  it("blocks when AAL2 MFA is not verified", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.approval.principal.assuranceLevel = "aal1";
      })
    );
    assertBlocked(result, "mfa_required");
  });

  it("blocks a stale step-up", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.approval.principal.stepUpSatisfiedAt = STALE;
      })
    );
    assertBlocked(result, "fresh_step_up_required");
  });

  it("blocks an empty audit reason", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.approval.auditReason = "   ";
      })
    );
    assertBlocked(result, "audit_reason_required");
  });

  it("blocks any delete operation in the diff", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.runReport.shipmentDiff.delete = 1;
        input.runReport.shipmentDiff.total = 4;
      })
    );
    assertBlocked(result, "delete_not_allowed");
  });

  it("blocks a non-narrow geography/category", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.bounds.geography = "IT,FR,ES";
      })
    );
    assertBlocked(result, "scope_not_narrow");
  });

  it("blocks when the write count exceeds the bound", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.bounds.maxRows = 2;
        input.runReport.shipmentDiff.insert = 5;
        input.runReport.shipmentDiff.total = 5;
      })
    );
    assertBlocked(result, "row_bound_exceeded");
  });

  it("blocks when there is nothing to ship", () => {
    const result = evaluateStagingCanaryPromotion(
      validInput((input) => {
        input.runReport.shipmentDiff.insert = 0;
        input.runReport.shipmentDiff.update = 0;
        input.runReport.shipmentDiff.noOp = 0;
        input.runReport.shipmentDiff.total = 0;
      })
    );
    assertBlocked(result, "nothing_to_ship");
  });
});

function assertBlocked(
  result: ReturnType<typeof evaluateStagingCanaryPromotion>,
  code: StagingCanaryBlockCode
): void {
  assert.equal(result.ok, false);
  if (result.ok) return;
  assert.ok(
    result.blocks.some((block) => block.code === code),
    `expected block "${code}", got [${result.blocks.map((block) => block.code).join(", ")}]`
  );
}

function validInput(
  mutate?: (input: EvaluateStagingCanaryPromotionInput) => void
): EvaluateStagingCanaryPromotionInput {
  const input: EvaluateStagingCanaryPromotionInput = {
    runReport: runReport(),
    transition: { from: "review_required", to: "staging_write" },
    targetEnvironment: "staging",
    approval: {
      principal: principal(),
      auditReason: "first Rome landmark canary",
      now: NOW
    },
    bounds: { geography: "Rome", category: "landmark" }
  };
  mutate?.(input);
  return input;
}

function diff(): ShipmentDiffSummary {
  return {
    compatible: true,
    insert: 2,
    update: 1,
    noOp: 4,
    delete: 0,
    total: 7,
    incompatibilities: 0
  };
}

function principal(): AdminPrincipal {
  return {
    provider: "supabase",
    userId: "user-1",
    email: "admin@confluendo.dev",
    role: "admin",
    scopes: ["vamo"],
    assuranceLevel: "aal2",
    hasVerifiedMfaFactor: true,
    mfaRequired: true,
    stepUpSatisfiedAt: FRESH
  };
}

function runReport(): ProgressiveRunReport {
  return {
    projectKey: "vamo",
    targetId: "vamo-place-intelligence",
    sourceId: "fsq-os-places",
    tier: "sample_dry_run",
    safetyMode: "dry_run",
    stages: [],
    currentStage: "review_required",
    preflight: { passed: true, checks: [], failures: [] },
    scout: {
      sampleRowCount: 7,
      candidateCount: 7,
      deadLetterCount: 0,
      policyBlockCount: 0,
      detail: "scout"
    },
    rowCounts: { read: 7, staged: 7, policyBlocked: 0, deadLettered: 0 },
    shipmentDiff: diff(),
    checkpoint: {
      cursorScope: "fsq-os-places",
      cursorValue: 7,
      lastRecordKey: "rec-7",
      processedCount: 7
    },
    policyBlocks: [],
    deadLetters: [],
    wroteToTarget: false,
    reachedReview: true,
    aiRationale: {
      generator: "policy_advisory_placeholder",
      recommendedTier: "staging_canary",
      confidence: "high",
      summary: "advisory",
      evidence: [],
      advisoryOnly: true
    },
    nextApproval: {
      required: true,
      role: "ingestion_admin",
      requireMfa: true,
      requireAuditReason: true,
      description: "approve canary"
    }
  };
}
