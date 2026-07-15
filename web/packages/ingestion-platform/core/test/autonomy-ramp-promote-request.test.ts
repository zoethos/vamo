import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

import { parseAutonomyRampPromoteRequest } from "../src/autonomy-ramp-promote-request.js";
import { presentAutonomyRampCard } from "../src/autonomy-ramp-presenter.js";
import type { AutonomyPolicyEnvelope } from "../src/autonomy-policy.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const rampRoute = join(
  webRoot,
  "apps/confluendo-console/app/api/admin/ingestion/autonomy/ramp/route.ts"
);

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
    maxUnitsPerCycle: 100,
    maxRowsPerCycle: 25000,
    rollingLimits: { maxCyclesPerDay: 999, maxUnitsPerDay: 999, maxRowsPerDay: 999 },
    guardThresholds: {},
    productionInboxHandoffPolicy: { requiresIp18_6: true },
    policyVersion: 1,
    rampMode: "staging_ramp",
    summary: { rampMode: "staging_ramp" },
    ...overrides
  };
}

describe("parseAutonomyRampPromoteRequest", () => {
  it("accepts a valid promotion body", () => {
    const parsed = parseAutonomyRampPromoteRequest({
      projectKey: "vamo",
      policyKey: "vamo-eu-poi-staging-v1",
      expectedCurrentMode: "staging_ramp",
      requestedMode: "volume_ramp",
      auditReason: "Readiness evidence looks acceptable.",
      confirmedMode: "volume_ramp",
      acknowledgedWarnings: true
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.request.requestedMode, "volume_ramp");
    assert.equal(parsed.request.acknowledgedWarnings, true);
  });

  it("rejects missing audit reason", () => {
    const parsed = parseAutonomyRampPromoteRequest({
      projectKey: "vamo",
      policyKey: "vamo-eu-poi-staging-v1",
      expectedCurrentMode: "staging_ramp",
      requestedMode: "volume_ramp",
      auditReason: "   ",
      confirmedMode: "volume_ramp"
    });
    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.equal(parsed.code, "audit_reason_required");
  });

  it("rejects confirmed mode mismatch", () => {
    const parsed = parseAutonomyRampPromoteRequest({
      projectKey: "vamo",
      policyKey: "vamo-eu-poi-staging-v1",
      expectedCurrentMode: "staging_ramp",
      requestedMode: "volume_ramp",
      auditReason: "Promote after review.",
      confirmedMode: "bootstrap"
    });
    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.equal(parsed.code, "confirmed_mode_mismatch");
  });
});

describe("presentAutonomyRampCard", () => {
  it("separates owner ceiling, profile caps, and effective bounds", () => {
    const card = presentAutonomyRampCard({
      policy: policy({ rampMode: "bootstrap", maxUnitsPerCycle: 100, maxRowsPerCycle: 25000 }),
      readiness: {
        policyId: "policy-1",
        policyKey: "vamo-eu-poi-staging-v1",
        currentMode: "bootstrap",
        since: "2026-07-01T00:00:00.000Z",
        runs: { advanced: 2, completed: 1, failed: 0, paused: 0 },
        stagingCanarySucceededUnits: 1
      },
      blockerSummaries: [],
      blockedUnitCount: 0
    });

    assert.equal(card.currentMode, "bootstrap");
    assert.equal(card.nextMode, "staging_ramp");
    assert.equal(card.ownerCeiling.maxUnitsPerCycle, 100);
    assert.equal(card.profileCaps.maxUnitsPerCycle, 1);
    assert.equal(card.effectiveBounds.maxUnitsPerCycle, 1);
    assert.ok(card.readinessEvidence.length > 0);
    assert.equal(card.advisoryWarnings.length, 0);
  });

  it("warns when no staging-verified evidence exists", () => {
    const card = presentAutonomyRampCard({
      policy: policy({ rampMode: "staging_ramp" }),
      readiness: {
        policyId: "policy-1",
        policyKey: "vamo-eu-poi-staging-v1",
        currentMode: "staging_ramp",
        since: "2026-07-01T00:00:00.000Z",
        runs: { advanced: 3, completed: 1, failed: 0, paused: 0 },
        stagingCanarySucceededUnits: 0
      },
      blockerSummaries: [],
      blockedUnitCount: 0
    });

    assert.ok(card.advisoryWarnings.some((warning) => warning.includes("No staging-verified scopes")));
  });
});

describe("autonomy ramp route artifact", () => {
  it("uses the core adapter and avoids delivery DSNs or direct SQL credentials", () => {
    const routeSource = readFileSync(rampRoute, "utf8");
    assert.match(routeSource, /promoteAutonomyRamp/);
    assert.match(routeSource, /evaluateAutonomyRampPromotion/);
    assert.match(routeSource, /parseAutonomyRampPromoteRequest/);
    assert.match(routeSource, /getActiveControlEnvironmentConfig/);
    assert.doesNotMatch(routeSource, /process\.env\.INGESTION_CONTROL_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /VAMO_STAGING_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /VAMO_PRODUCTION_INBOX_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /update ingestion_platform\.ingestion_autonomy_policies/i);
    assert.doesNotMatch(routeSource, /process\.env\.[A-Z_]*PASSWORD/i);
  });

  it("requires fresh step-up only through the pure promotion policy path", () => {
    const routeSource = readFileSync(rampRoute, "utf8");
    assert.match(routeSource, /hasFreshAdminStepUp/);
    assert.match(routeSource, /acknowledgedWarnings/);
  });
});
