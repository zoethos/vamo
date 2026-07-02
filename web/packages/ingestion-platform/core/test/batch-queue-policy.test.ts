import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { AdminPrincipal } from "../src/admin-auth.js";
import { evaluateBatchQueueScheduleDryRun } from "../src/batch-queue-policy.js";
import { sampleVamoEuPoiBatchQueueSnapshot } from "../src/batch-queue-read-model.js";

describe("batch queue dry-run scheduling policy", () => {
  it("approves an AAL2 operator scoped to the project with ready queue items", () => {
    const result = evaluateBatchQueueScheduleDryRun({
      projectKey: "vamo",
      snapshot: sampleVamoEuPoiBatchQueueSnapshot(),
      principal: principal(),
      auditReason: "schedule the first EU POI dry-run batch"
    });

    assert.equal(result.ok, true);
    if (!result.ok) {
      throw new Error("expected approval");
    }
    assert.equal(result.plan.action, "schedule_dry_run_batch");
    assert.equal(result.plan.projectKey, "vamo");
    assert.equal(result.plan.targetKey, "vamo-place-intelligence");
    assert.equal(result.plan.targetEnvironment, "staging");
    assert.equal(result.plan.fromStatus, "ready_for_dry_run");
    assert.equal(result.plan.toStatus, "dry_run_ready");
    assert.equal(result.plan.itemCount, 36);
    assert.equal(result.plan.unitKeys.length, 36);
    assert.equal(result.plan.auditReason, "schedule the first EU POI dry-run batch");
  });

  it("blocks viewers, missing project scope, missing MFA, and missing reason", () => {
    const result = evaluateBatchQueueScheduleDryRun({
      projectKey: "vamo",
      snapshot: sampleVamoEuPoiBatchQueueSnapshot(),
      principal: principal({
        role: "viewer",
        scopes: ["other"],
        assuranceLevel: "aal1",
        hasVerifiedMfaFactor: false
      }),
      auditReason: " "
    });

    assert.equal(result.ok, false);
    if (result.ok) {
      throw new Error("expected blocks");
    }
    assert.deepEqual(
      result.blocks.map((block) => block.code).sort(),
      ["audit_reason_required", "mfa_required", "role_denied", "scope_denied"]
    );
  });

  it("blocks unsafe plan metadata and already-scheduled queues", () => {
    const scheduled = sampleVamoEuPoiBatchQueueSnapshot();
    const result = evaluateBatchQueueScheduleDryRun({
      projectKey: "vamo",
      snapshot: {
        ...scheduled,
        safetyMode: "approved_write",
        items: scheduled.items.map((item) => ({ ...item, status: "dry_run_ready" }))
      },
      principal: principal(),
      auditReason: "schedule batch"
    });

    assert.equal(result.ok, false);
    if (result.ok) {
      throw new Error("expected blocks");
    }
    assert.deepEqual(
      result.blocks.map((block) => block.code).sort(),
      ["no_eligible_items", "unsafe_safety_mode"]
    );
  });
});

function principal(overrides: Partial<AdminPrincipal> = {}): AdminPrincipal {
  return {
    provider: "supabase",
    userId: "user-1",
    email: "operator@example.com",
    role: "operator",
    scopes: ["vamo"],
    assuranceLevel: "aal2",
    hasVerifiedMfaFactor: true,
    mfaRequired: true,
    ...overrides
  };
}
