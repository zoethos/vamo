import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { AutonomyPolicyEnvelope } from "../src/autonomy-policy.js";
import {
  AUTONOMY_RAMP_PROFILES,
  evaluateAutonomyRampPromotion,
  readAutonomyRampMode,
  resolveAutonomyRamp
} from "../src/autonomy-ramp-policy.js";

function policy(overrides: Partial<AutonomyPolicyEnvelope> = {}): AutonomyPolicyEnvelope {
  return {
    policyId: "policy-1",
    policyKey: "vamo-eu-poi-staging-v1",
    projectKey: "vamo",
    sourceKey: "fsq-os-places-sample",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    status: "active",
    allowedTiers: ["sample_dry_run"],
    allowedGeographies: [],
    allowedCategories: [],
    allowedTransitions: ["schedule_dry_run", "execute_dry_run", "approve_staging_wave"],
    maxUnitsPerCycle: 1,
    maxRowsPerCycle: 2,
    rollingLimits: { maxCyclesPerDay: 4, maxUnitsPerDay: 2, maxRowsPerDay: 4 },
    guardThresholds: {},
    productionInboxHandoffPolicy: { enabled: false, requiresIp18_6: true },
    policyVersion: 1,
    summary: { ramp: { mode: "bootstrap" } },
    ...overrides
  };
}

describe("autonomy ramp policy", () => {
  it("defaults missing ramp metadata to bootstrap", () => {
    assert.equal(readAutonomyRampMode(undefined), "bootstrap");
    assert.equal(readAutonomyRampMode({ note: "legacy policy" }), "bootstrap");
  });

  it("reads nested or direct ramp mode metadata", () => {
    assert.equal(readAutonomyRampMode({ ramp: { mode: "staging_ramp" } }), "staging_ramp");
    assert.equal(readAutonomyRampMode({ rampMode: "volume_ramp" }), "volume_ramp");
  });

  it("resolves bootstrap profile and recommended next mode", () => {
    const ramp = resolveAutonomyRamp(policy());
    assert.equal(ramp.mode, "bootstrap");
    assert.equal(ramp.recommendedNextMode, "staging_ramp");
    assert.equal(ramp.profile.maxUnitsPerCycle, 1);
    assert.equal(ramp.policyWithinProfile, true);
  });

  it("warns when a policy exceeds its declared mode profile", () => {
    const ramp = resolveAutonomyRamp(
      policy({
        maxUnitsPerCycle: 3,
        rollingLimits: { maxUnitsPerDay: 10, maxRowsPerDay: 4, maxCyclesPerDay: 4 }
      })
    );
    assert.equal(ramp.policyWithinProfile, false);
    assert.ok(ramp.warnings.some((warning) => warning.includes("max_units_per_cycle")));
    assert.ok(ramp.warnings.some((warning) => warning.includes("maxUnitsPerDay")));
  });

  it("allows only the next adjacent ramp promotion by an admin operator", () => {
    const result = evaluateAutonomyRampPromotion({
      currentMode: "bootstrap",
      requestedMode: "staging_ramp",
      actor: { type: "operator", id: "dba@example.com", role: "admin" },
      auditReason: "Two bootstrap autonomy cycles succeeded; widen to staging ramp."
    });
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.profile, AUTONOMY_RAMP_PROFILES.staging_ramp);
      assert.equal(result.toMode, "staging_ramp");
    }
  });

  it("blocks skipped ramp promotions and autonomous self-widening", () => {
    const result = evaluateAutonomyRampPromotion({
      currentMode: "bootstrap",
      requestedMode: "volume_ramp",
      actor: { type: "autonomous_agent", id: "agent" },
      auditReason: "go faster"
    });
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.ok(result.blocks.some((block) => block.code === "skips_required_ramp"));
      assert.ok(result.blocks.some((block) => block.code === "actor_not_operator"));
    }
  });

  it("blocks steady state until production handoff telemetry is supported", () => {
    const result = evaluateAutonomyRampPromotion({
      currentMode: "volume_ramp",
      requestedMode: "steady_state",
      actor: { type: "operator", id: "dba@example.com", role: "admin" },
      auditReason: "production ramp",
      productionInboxSupported: false
    });
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.equal(result.blocks[0]?.code, "production_handoff_not_ready");
    }
  });
});
