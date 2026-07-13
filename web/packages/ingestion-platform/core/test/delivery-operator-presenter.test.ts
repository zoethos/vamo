import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";
import {
  approvalButtonDisabledReason,
  approvalEnvelopeOverrideWarning,
  applyButtonDisabledReason,
  applyButtonLabel,
  deriveProductionPackageApprovalEnvelope
} from "../src/delivery-operator-presenter.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const approvalControlPath = join(
  webRoot,
  "apps/confluendo-console/app/admin/ingestion/production-package-wave-approval-control.tsx"
);

describe("deriveProductionPackageApprovalEnvelope", () => {
  it("derives caps from ten selected scopes", () => {
    const envelope = deriveProductionPackageApprovalEnvelope({
      selectedScopes: 10,
      expectedTargetWrites: 42,
      hasPriorDeliveredPackage: true
    });
    assert.equal(envelope.selectedScopes, 10);
    assert.equal(envelope.expectedPackages, 10);
    assert.equal(envelope.expectedTargetWrites, 42);
    assert.equal(envelope.maxUnits, 10);
    assert.equal(envelope.maxPackages, 10);
    assert.equal(envelope.maxTargetWrites, 42);
    assert.equal(envelope.rampCapLabel, null);
    assert.equal(envelope.exceedsRampCap, false);
  });

  it("flags first-wave ramp cap when more than one scope is selected", () => {
    const envelope = deriveProductionPackageApprovalEnvelope({
      selectedScopes: 10,
      expectedTargetWrites: 20,
      hasPriorDeliveredPackage: false
    });
    assert.match(envelope.rampCapLabel ?? "", /First live wave/);
    assert.equal(envelope.exceedsRampCap, true);
    assert.equal(envelope.maxUnits, 10);
  });

  it("warns when advanced override is below selection", () => {
    const envelope = deriveProductionPackageApprovalEnvelope({
      selectedScopes: 10,
      expectedTargetWrites: 30,
      hasPriorDeliveredPackage: true,
      override: { maxUnits: 5, maxPackages: 5, maxTargetWrites: 30 }
    });
    const warning = approvalEnvelopeOverrideWarning(envelope, {
      maxUnits: 5,
      maxPackages: 5,
      maxTargetWrites: 30
    });
    assert.match(warning ?? "", /Max units override/);
  });
});

describe("apply operator presenter", () => {
  it("labels preflight and apply phases", () => {
    assert.equal(
      applyButtonLabel({ preflightPhase: "checking", applyPhase: "idle", selectedCount: 3 }),
      "Checking apply preflight…"
    );
    assert.equal(
      applyButtonLabel({ preflightPhase: "idle", applyPhase: "applying", selectedCount: 3 }),
      "Applying 3 packages to Vamo…"
    );
  });

  it("explains disabled state during preflight", () => {
    const reason = applyButtonDisabledReason({
      preflightPhase: "checking",
      applyPhase: "idle",
      inFlight: false,
      selectedCount: 2,
      auditReason: "ready",
      preflightBlocks: [],
      hasPreflight: false
    });
    assert.match(reason ?? "", /Checking apply preflight/);
  });
});

describe("approval operator presenter", () => {
  it("requires audit reason before approval", () => {
    const envelope = deriveProductionPackageApprovalEnvelope({
      selectedScopes: 2,
      expectedTargetWrites: 8,
      hasPriorDeliveredPackage: true
    });
    const reason = approvalButtonDisabledReason({
      phase: "idle",
      eligibleCount: 5,
      selectedCount: 2,
      auditReason: "   ",
      envelope
    });
    assert.match(reason ?? "", /audit reason/i);
  });
});

describe("production package-wave approval control artifact", () => {
  it("does not reference production inbox DSN env vars", () => {
    const source = readFileSync(approvalControlPath, "utf8");
    assert.doesNotMatch(source, /VAMO_PRODUCTION_INBOX_DATABASE_URL/);
  });
});
