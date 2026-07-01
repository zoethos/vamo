import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { AdminPrincipal } from "../src/admin-auth.js";
import {
  evaluateProductionInboxPromotion,
  isProductionInboxApprovalFresh
} from "../src/production-inbox-policy.js";
import { sampleProgressiveRunSnapshot } from "../src/progressive-read-model.js";

const report = sampleProgressiveRunSnapshot.entries[0]?.report;
if (!report) {
  throw new Error("sample progressive report missing");
}

describe("production inbox promotion policy", () => {
  it("approves a reviewed dry run with succeeded staging canary evidence", () => {
    const decision = evaluateProductionInboxPromotion({
      runReport: report,
      transition: {
        from: "approved_for_production_inbox",
        to: "production_inbox_delivered"
      },
      targetEnvironment: "production",
      stagingCanary: {
        status: "succeeded",
        shipmentKey: "staging-canary:vamo-place-intelligence-staging:approval:8",
        approvalAuditId: "8"
      },
      bounds: { geography: "rome-italy", category: "poi", maxRows: 2 },
      approval: {
        principal: admin(),
        auditReason: "Production inbox smoke after staging canary success.",
        now: "2026-07-01T10:04:00.000Z"
      }
    });

    assert.equal(decision.ok, true);
    if (!decision.ok) return;
    assert.equal(decision.plan.targetEnvironment, "production");
    assert.equal(decision.plan.toStatus, "production_inbox_delivered");
    assert.equal(decision.plan.schemaContract, "vamo-place-intelligence@1");
    assert.equal(decision.plan.write.writeCount, 2);
    assert.equal(decision.plan.stagingCanary.approvalAuditId, "8");
  });

  it("blocks when staging canary evidence is missing", () => {
    const decision = evaluateProductionInboxPromotion({
      runReport: report,
      transition: {
        from: "approved_for_production_inbox",
        to: "production_inbox_delivered"
      },
      targetEnvironment: "production",
      bounds: { geography: "rome-italy", category: "poi", maxRows: 2 },
      approval: {
        principal: admin(),
        auditReason: "missing evidence",
        now: "2026-07-01T10:04:00.000Z"
      }
    });

    assert.equal(decision.ok, false);
    if (decision.ok) return;
    assert.ok(decision.blocks.some((block) => block.code === "staging_canary_required"));
  });

  it("blocks production delivery for stale MFA, non-production env, deletes, and widened bounds", () => {
    const dirtyReport = {
      ...report,
      shipmentDiff: { ...report.shipmentDiff, delete: 1 }
    };
    const decision = evaluateProductionInboxPromotion({
      runReport: dirtyReport,
      transition: {
        from: "approved_for_production_inbox",
        to: "production_inbox_delivered"
      },
      targetEnvironment: "staging",
      stagingCanary: { status: "succeeded" },
      bounds: { geography: "*", category: "poi", maxRows: 2 },
      approval: {
        principal: admin({ stepUpSatisfiedAt: "2026-07-01T09:00:00.000Z" }),
        auditReason: "bad gate",
        now: "2026-07-01T10:04:00.000Z"
      }
    });

    assert.equal(decision.ok, false);
    if (decision.ok) return;
    assert.deepEqual(
      decision.blocks.map((block) => block.code).filter((code) =>
        [
          "not_production_environment",
          "fresh_step_up_required",
          "delete_not_allowed",
          "scope_not_narrow"
        ].includes(code)
      ),
      [
        "not_production_environment",
        "fresh_step_up_required",
        "delete_not_allowed",
        "scope_not_narrow"
      ]
    );
  });

  it("treats approval freshness as bounded and fails closed on future timestamps", () => {
    assert.equal(
      isProductionInboxApprovalFresh({
        approvedAt: "2026-07-01T10:00:00.000Z",
        now: "2026-07-01T10:10:00.000Z",
        maxAgeMs: 15 * 60 * 1000
      }),
      true
    );
    assert.equal(
      isProductionInboxApprovalFresh({
        approvedAt: "2026-07-01T10:20:00.000Z",
        now: "2026-07-01T10:10:00.000Z"
      }),
      false
    );
  });
});

function admin(overrides: Partial<AdminPrincipal> = {}): AdminPrincipal {
  return {
    provider: "supabase",
    userId: "user-1",
    email: "dba.confluendo@outlook.com",
    role: "admin",
    scopes: ["vamo"],
    assuranceLevel: "aal2",
    hasVerifiedMfaFactor: true,
    mfaRequired: true,
    stepUpSatisfiedAt: "2026-07-01T10:00:00.000Z",
    ...overrides
  };
}
