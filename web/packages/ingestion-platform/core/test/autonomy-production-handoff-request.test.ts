import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

import {
  evaluateAutonomyProductionHandoffChange,
  parseAutonomyProductionHandoffRequest,
  presentAutonomyProductionHandoffCard
} from "../src/index.js";
import type { AutonomyPolicyEnvelope } from "../src/autonomy-policy.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const handoffRoute = join(
  webRoot,
  "apps/confluendo-console/app/api/admin/ingestion/autonomy/production-handoff/route.ts"
);

function policy(overrides: Partial<AutonomyPolicyEnvelope> = {}): AutonomyPolicyEnvelope {
  return {
    policyId: "policy-1",
    policyKey: "vamo-eu-poi-staging-v1",
    projectKey: "vamo",
    sourceKey: "fsq-os-places-snapshot",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    status: "active",
    allowedTiers: ["sample_dry_run"],
    allowedGeographies: [],
    allowedCategories: [],
    allowedTransitions: ["schedule_dry_run", "execute_dry_run", "approve_staging_wave"],
    maxUnitsPerCycle: 100,
    maxRowsPerCycle: 25000,
    rollingLimits: { maxCyclesPerDay: 100, maxUnitsPerDay: 200, maxRowsPerDay: 2000 },
    guardThresholds: {},
    productionInboxHandoffPolicy: { requiresIp18_6: true },
    policyVersion: 1,
    rampMode: "volume_ramp",
    summary: { rampMode: "volume_ramp" },
    ...overrides
  };
}

describe("parseAutonomyProductionHandoffRequest", () => {
  it("accepts a valid enable request", () => {
    const parsed = parseAutonomyProductionHandoffRequest({
      projectKey: "vamo",
      policyKey: "vamo-eu-poi-staging-v1",
      expectedEnabled: false,
      requestedEnabled: true,
      auditReason: "Allow autonomous production package handoff after live proof.",
      confirmedState: "enabled"
    });

    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.request.requestedEnabled, true);
    assert.equal(parsed.request.confirmedState, "enabled");
  });

  it("rejects missing audit reason", () => {
    const parsed = parseAutonomyProductionHandoffRequest({
      projectKey: "vamo",
      policyKey: "vamo-eu-poi-staging-v1",
      expectedEnabled: false,
      requestedEnabled: true,
      auditReason: "   ",
      confirmedState: "enabled"
    });

    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.equal(parsed.code, "audit_reason_required");
  });

  it("rejects confirmation state mismatch", () => {
    const parsed = parseAutonomyProductionHandoffRequest({
      projectKey: "vamo",
      policyKey: "vamo-eu-poi-staging-v1",
      expectedEnabled: false,
      requestedEnabled: true,
      auditReason: "Enable handoff.",
      confirmedState: "disabled"
    });

    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.equal(parsed.code, "confirmed_state_mismatch");
  });
});

describe("presentAutonomyProductionHandoffCard", () => {
  it("treats requiresIp18_6 as disabled even if enabled is present", () => {
    const card = presentAutonomyProductionHandoffCard(
      policy({ productionInboxHandoffPolicy: { enabled: true, requiresIp18_6: true } })
    );

    assert.equal(card.enabled, false);
    assert.equal(card.state, "disabled");
    assert.equal(card.requestedState, "enabled");
    assert.ok(card.deniedActions.some((action) => action.includes("Apply delivered packages")));
  });

  it("presents enabled production handoff without enabling consumer apply", () => {
    const card = presentAutonomyProductionHandoffCard(
      policy({
        productionInboxHandoffPolicy: {
          enabled: true,
          requiresIp18_6: false,
          consumerApplyEnabled: false
        }
      })
    );

    assert.equal(card.enabled, true);
    assert.equal(card.state, "enabled");
    assert.equal(card.requestedState, "disabled");
    assert.ok(card.allowedActions.some((action) => action.includes("Deliver approved")));
    assert.ok(card.deniedActions.some((action) => action.includes("Apply delivered")));
  });
});

describe("evaluateAutonomyProductionHandoffChange", () => {
  it("requires admin and fresh AAL2 step-up when enabling", () => {
    const decision = evaluateAutonomyProductionHandoffChange({
      currentEnabled: false,
      requestedEnabled: true,
      actor: {
        type: "operator",
        id: "dba@example.com",
        role: "admin",
        assuranceLevel: "aal1",
        stepUpFresh: false
      },
      auditReason: "Enable after review."
    });

    assert.equal(decision.ok, false);
    if (decision.ok) return;
    assert.ok(decision.blocks.some((block) => block.code === "fresh_step_up_required"));
  });

  it("allows disabling without a fresh step-up", () => {
    const decision = evaluateAutonomyProductionHandoffChange({
      currentEnabled: true,
      requestedEnabled: false,
      actor: {
        type: "operator",
        id: "dba@example.com",
        role: "admin",
        assuranceLevel: "aal1",
        stepUpFresh: false
      },
      auditReason: "Disable while investigating package delivery."
    });

    assert.equal(decision.ok, true);
    if (!decision.ok) return;
    assert.equal(decision.direction, "disable");
  });
});

describe("production handoff route artifact", () => {
  it("uses the core adapter and avoids consumer database write paths", () => {
    const routeSource = readFileSync(handoffRoute, "utf8");
    assert.match(routeSource, /setAutonomyProductionHandoff/);
    assert.match(routeSource, /evaluateAutonomyProductionHandoffChange/);
    assert.match(routeSource, /parseAutonomyProductionHandoffRequest/);
    assert.match(routeSource, /getActiveControlEnvironmentConfig/);
    assert.doesNotMatch(routeSource, /process\.env\.INGESTION_CONTROL_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /VAMO_STAGING_CANARY_APP_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /VAMO_PRODUCTION_INBOX_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /applyPostgres/i);
    assert.doesNotMatch(routeSource, /update ingestion_platform\.ingestion_autonomy_policies/i);
  });
});
