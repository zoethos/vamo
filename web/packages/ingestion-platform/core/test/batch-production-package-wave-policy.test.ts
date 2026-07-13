import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { AdminPrincipal } from "../src/admin-auth.js";
import {
  buildBatchQueueSnapshotFromItems,
  type BatchQueueItem
} from "../src/batch-queue-read-model.js";
import {
  PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS,
  isProductionInboxApprovalFresh
} from "../src/production-inbox-policy.js";
import {
  VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
  buildProductionPackageWaveKey,
  countStagingProvenPackageEligibleUnits,
  evaluateProductionPackageWaveApproval,
  evaluateProductionPackageWaveDeliveryDrift,
  evaluateProductionPackageWaveEligibility,
  finalizeProductionPackageWaveApprovalPlan,
  isApprovedProductionPackageWaveFresh,
  isLegacyProductionTargetKey,
  type BatchProductionPackageWaveBlockCode
} from "../src/batch-production-package-wave-policy.js";

const NOW = "2026-07-07T10:00:00.000Z";
const FRESH = "2026-07-07T09:58:00.000Z";
const STALE = "2026-07-07T08:00:00.000Z";

describe("evaluateProductionPackageWaveEligibility", () => {
  it("accepts a staging-proven unit with valid evidence", () => {
    const result = evaluateProductionPackageWaveEligibility(validEligibilityInput());
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.selectedUnits.length, 1);
    assert.equal(result.totalPlannedRows, 2);
  });

  it("blocks non-production environment", () => {
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({ targetEnvironment: "staging" })
    );
    assertBlocked(result, "not_production_environment");
  });

  it("blocks legacy target keys", () => {
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({ targetKey: "vamo-place-intelligence-staging" })
    );
    assertBlocked(result, "legacy_target_key");
    assert.equal(isLegacyProductionTargetKey("vamo-place-intelligence-staging"), true);
  });

  it("blocks schema contract mismatch", () => {
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({ schemaContract: "vamo-place-intelligence@2" })
    );
    assertBlocked(result, "schema_contract_mismatch");
  });

  it("blocks missing staging evidence", () => {
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({ stagingEvidenceByUnitKey: {} })
    );
    assertBlocked(result, "staging_canary_required");
  });

  it("blocks failed staging evidence", () => {
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({
        stagingEvidenceByUnitKey: {
          "unit-a": { status: "failed", shipmentKey: "ship:1" }
        }
      })
    );
    assertBlocked(result, "staging_canary_not_succeeded");
  });

  it("blocks dry-run wroteToTarget violations", () => {
    const snapshot = snapshotWithItems([
      stagingProvenItem("unit-a", {
        dryRunReport: {
          wroteToTarget: true as unknown as false,
          rowsProcessed: 1,
          insertCount: 1,
          updateCount: 0,
          noOpCount: 0
        }
      })
    ]);
    const result = evaluateProductionPackageWaveEligibility(validEligibilityInput({ snapshot }));
    assertBlocked(result, "dry_run_invariant_violated");
  });

  it("blocks deletes", () => {
    const snapshot = snapshotWithItems([
      stagingProvenItem("unit-a", {
        dryRunReport: {
          wroteToTarget: false,
          rowsProcessed: 1,
          insertCount: 1,
          updateCount: 0,
          noOpCount: 0,
          deleteCount: 1
        } as BatchQueueItem["dryRunReport"]
      })
    ]);
    const result = evaluateProductionPackageWaveEligibility(validEligibilityInput({ snapshot }));
    assertBlocked(result, "delete_not_allowed");
  });

  it("blocks active blockers", () => {
    const snapshot = snapshotWithItems([
      stagingProvenItem("unit-a", { blockReasons: ["diff drift"] })
    ]);
    const result = evaluateProductionPackageWaveEligibility(validEligibilityInput({ snapshot }));
    assertBlocked(result, "active_blockers");
  });

  it("enforces unit, row, and package bounds", () => {
    const snapshot = snapshotWithItems([
      stagingProvenItem("unit-a", { writeCount: 5 }),
      stagingProvenItem("unit-b", { writeCount: 5 })
    ]);
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({
        snapshot,
        maxUnits: 1,
        maxRows: 6,
        maxPackages: 1,
        hasPriorDeliveredPackage: true,
        stagingEvidenceByUnitKey: {
          "unit-a": { status: "succeeded", shipmentKey: "s:1" },
          "unit-b": { status: "succeeded", shipmentKey: "s:2" }
        }
      })
    );
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.selectedUnits.length, 1);
    assert.equal(result.totalPlannedRows, 5);
  });

  it("blocks first wave over 1 unit", () => {
    const snapshot = snapshotWithItems([
      stagingProvenItem("unit-a"),
      stagingProvenItem("unit-b")
    ]);
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({
        snapshot,
        maxUnits: 2,
        stagingEvidenceByUnitKey: {
          "unit-a": { status: "succeeded" },
          "unit-b": { status: "succeeded" }
        }
      })
    );
    assertBlocked(result, "first_wave_ramp_exceeded");
  });

  it("blocks already delivered or pending apply units", () => {
    const snapshot = snapshotWithItems([stagingProvenItem("unit-a")]);
    const occupied = new Set(["unit-a"]);
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({ snapshot, occupiedUnitKeys: occupied })
    );
    assertBlocked(result, "already_delivered_or_pending_apply");
  });

  it("does not count a prior-plan-applied scope as package eligible", () => {
    const snapshot = snapshotWithItems([
      stagingProvenItem("unit-a", {
        crossPlanPackageLifecycle: {
          planKey: "vamo-eu-poi-sample",
          waveKey: "batch-production-inbox:vamo-eu-poi-sample:wave:58:unit:unit-a",
          status: "consumer_applied"
        }
      })
    ]);

    assert.equal(
      countStagingProvenPackageEligibleUnits(
        snapshot,
        "vamo-place-intelligence",
        { "unit-a": { status: "succeeded", shipmentKey: "staging:unit-a" } }
      ),
      0
    );
  });

  it("selects explicit multi-unit keys when all are staging verified", () => {
    const snapshot = snapshotWithItems([
      stagingProvenItem("unit-a", { runOrder: 1 }),
      stagingProvenItem("unit-b", { runOrder: 2 }),
      stagingProvenItem("unit-c", { runOrder: 3 })
    ]);
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({
        snapshot,
        maxUnits: 3,
        maxPackages: 3,
        maxRows: 10,
        hasPriorDeliveredPackage: true,
        unitKeys: ["unit-c", "unit-a"],
        stagingEvidenceByUnitKey: {
          "unit-a": { status: "succeeded", shipmentKey: "s:1" },
          "unit-b": { status: "succeeded", shipmentKey: "s:2" },
          "unit-c": { status: "succeeded", shipmentKey: "s:3" }
        }
      })
    );
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.deepEqual(
      result.selectedUnits.map((unit) => unit.item.unitKey),
      ["unit-a", "unit-c"]
    );
  });

  it("rejects stale explicit unit with per-unit reason", () => {
    const snapshot = snapshotWithItems([
      stagingProvenItem("unit-a"),
      stagingProvenItem("unit-b", { status: "blocked" })
    ]);
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({
        snapshot,
        unitKeys: ["unit-b"],
        hasPriorDeliveredPackage: true,
        stagingEvidenceByUnitKey: {
          "unit-a": { status: "succeeded", shipmentKey: "s:1" },
          "unit-b": { status: "succeeded", shipmentKey: "s:2" }
        }
      })
    );
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.ok(result.unitIssues?.some((issue) => issue.unitKey === "unit-b"));
  });

  it("enforces explicit maxUnits using expected target writes", () => {
    const snapshot = snapshotWithItems([
      stagingProvenItem("unit-a", { writeCount: 4 }),
      stagingProvenItem("unit-b", { runOrder: 2, writeCount: 4 }),
      stagingProvenItem("unit-c", { runOrder: 3, writeCount: 4 })
    ]);
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({
        snapshot,
        maxUnits: 2,
        maxRows: 10,
        maxPackages: 3,
        hasPriorDeliveredPackage: true,
        unitKeys: ["unit-a", "unit-b", "unit-c"],
        stagingEvidenceByUnitKey: {
          "unit-a": { status: "succeeded" },
          "unit-b": { status: "succeeded" },
          "unit-c": { status: "succeeded" }
        }
      })
    );
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.ok(
      result.unitIssues?.some((issue) => issue.code === "unit_selection_exceeds_max_units")
    );
  });

  it("keeps greedy fallback when unitKeys is omitted", () => {
    const snapshot = snapshotWithItems([
      stagingProvenItem("unit-a", { runOrder: 1 }),
      stagingProvenItem("unit-b", { runOrder: 2 })
    ]);
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({
        snapshot,
        maxUnits: 1,
        maxPackages: 1,
        hasPriorDeliveredPackage: true,
        stagingEvidenceByUnitKey: {
          "unit-a": { status: "succeeded" },
          "unit-b": { status: "succeeded" }
        }
      })
    );
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.deepEqual(result.selectedUnits.map((unit) => unit.item.unitKey), ["unit-a"]);
  });

  it("allows a 5-unit bounded wave after prior delivered package exists", () => {
    const items = Array.from({ length: 6 }, (_, index) =>
      stagingProvenItem(`unit-${index}`, { runOrder: index + 1 })
    );
    const snapshot = snapshotWithItems(items);
    const stagingEvidenceByUnitKey = Object.fromEntries(
      items.map((item) => [item.unitKey, { status: "succeeded", shipmentKey: `s:${item.unitKey}` }])
    );
    const result = evaluateProductionPackageWaveEligibility(
      validEligibilityInput({
        snapshot,
        maxUnits: 5,
        maxPackages: 5,
        maxRows: 20,
        hasPriorDeliveredPackage: true,
        unitKeys: items.slice(0, 5).map((item) => item.unitKey),
        stagingEvidenceByUnitKey
      })
    );
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.selectedUnits.length, 5);
  });
});

describe("evaluateProductionPackageWaveApproval", () => {
  it("accepts admin + AAL2 + fresh step-up and exposes 15-minute expiry", () => {
    const result = evaluateProductionPackageWaveApproval(validApprovalInput());
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.plan.targetEnvironment, "production");
    assert.equal(result.plan.schemaContract, VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT);
    assert.equal(result.plan.unitKeys.length, 1);
    const finalized = finalizeProductionPackageWaveApprovalPlan(result.plan, "audit:99");
    assert.equal(
      finalized.waveKey,
      buildProductionPackageWaveKey("vamo-eu-poi-sample", "audit:99", "unit-a")
    );
    const expiresMs =
      Date.parse(result.plan.approvalExpiresAt) - Date.parse(result.plan.approvedAt);
    assert.equal(expiresMs, PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS);
    assert.equal(
      isApprovedProductionPackageWaveFresh({
        approvedAt: result.plan.approvedAt,
        now: NOW
      }),
      true
    );
    assert.equal(
      isProductionInboxApprovalFresh({
        approvedAt: result.plan.approvedAt,
        now: new Date(Date.parse(result.plan.approvedAt) + PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS + 1).toISOString()
      }),
      false
    );
  });

  it("requires admin role", () => {
    const result = evaluateProductionPackageWaveApproval(
      validApprovalInput({ principal: adminPrincipal({ role: "operator" }) })
    );
    assertBlocked(result, "role_denied");
  });

  it("requires fresh MFA step-up", () => {
    const result = evaluateProductionPackageWaveApproval(
      validApprovalInput({ principal: adminPrincipal({ stepUpSatisfiedAt: STALE }) })
    );
    assertBlocked(result, "fresh_step_up_required");
  });

  it("requires audit reason", () => {
    const result = evaluateProductionPackageWaveApproval(validApprovalInput({ auditReason: "  " }));
    assertBlocked(result, "audit_reason_required");
  });
});

describe("evaluateProductionPackageWaveDeliveryDrift", () => {
  it("detects queue status and evidence drift for future delivery recheck", () => {
    const eligibility = evaluateProductionPackageWaveEligibility(validEligibilityInput());
    assert.equal(eligibility.ok, true);
    if (!eligibility.ok) return;
    const selected = eligibility.selectedUnits[0]!;

    const driftBlocks = evaluateProductionPackageWaveDeliveryDrift({
      approvedUnit: selected,
      currentItem: { ...selected.item, status: "blocked" },
      currentStagingEvidence: { status: "failed" },
      expectedSchemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
      storedChecksum: "abc",
      incomingChecksum: "def"
    });
    assert.ok(driftBlocks.some((block) => block.code === "queue_status_drift"));
    assert.ok(driftBlocks.some((block) => block.code === "staging_evidence_drift"));
    assert.ok(driftBlocks.some((block) => block.code === "checksum_incompatible"));
  });

  it("distinguishes delivered from consumer-applied in drift checks via status", () => {
    const eligibility = evaluateProductionPackageWaveEligibility(validEligibilityInput());
    assert.equal(eligibility.ok, true);
    if (!eligibility.ok) return;
    const selected = eligibility.selectedUnits[0]!;

    const deliveredBlocks = evaluateProductionPackageWaveDeliveryDrift({
      approvedUnit: selected,
      currentItem: { ...selected.item, status: "production_package_delivered" },
      expectedSchemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT
    });
    assert.equal(deliveredBlocks.length, 0);

    const failedApplyBlocks = evaluateProductionPackageWaveDeliveryDrift({
      approvedUnit: selected,
      currentItem: { ...selected.item, status: "consumer_apply_failed" },
      expectedSchemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT
    });
    assert.ok(failedApplyBlocks.some((block) => block.code === "queue_status_drift"));
  });
});

function validEligibilityInput(
  overrides: Partial<Parameters<typeof evaluateProductionPackageWaveEligibility>[0]> = {}
) {
  return {
    snapshot: snapshotWithItems([stagingProvenItem("unit-a")]),
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "production",
    schemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
    maxUnits: 1,
    maxRows: 10,
    maxPackages: 1,
    stagingEvidenceByUnitKey: {
      "unit-a": { status: "succeeded", shipmentKey: "staging:unit-a", shipmentId: "42" }
    },
    ...overrides
  };
}

function validApprovalInput(
  overrides: Partial<Parameters<typeof evaluateProductionPackageWaveApproval>[0]> = {}
) {
  return {
    projectKey: "vamo",
    snapshot: snapshotWithItems([stagingProvenItem("unit-a")]),
    principal: adminPrincipal(),
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "production",
    schemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
    maxUnits: 1,
    maxRows: 10,
    maxPackages: 1,
    auditReason: "Approve first production package wave.",
    stagingEvidenceByUnitKey: {
      "unit-a": { status: "succeeded", shipmentKey: "staging:unit-a" }
    },
    now: NOW,
    ...overrides
  };
}

function snapshotWithItems(items: BatchQueueItem[]) {
  return buildBatchQueueSnapshotFromItems({
    planId: "vamo-eu-poi-sample",
    projectKey: "vamo",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    sourceKey: "fsq-os-places-sample",
    safetyMode: "dry_run",
    items
  });
}

function stagingProvenItem(
  unitKey: string,
  overrides: Partial<BatchQueueItem> & { writeCount?: number } = {}
): BatchQueueItem {
  const writeCount = overrides.writeCount ?? 2;
  return {
    unitKey,
    runOrder: overrides.runOrder ?? 1,
    geography: "paris",
    geographyKind: "city",
    country: "france",
    category: "landmark",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    sourceKey: "fsq-os-places-sample",
    priority: 1,
    status: "staging_canary_succeeded",
    blockReasons: [],
    dryRunReport: {
      wroteToTarget: false,
      rowsProcessed: writeCount,
      insertCount: writeCount,
      updateCount: 0,
      noOpCount: 0,
      executionKey: `dry-run:${unitKey}`
    },
    ...overrides
  };
}

function adminPrincipal(overrides: Partial<AdminPrincipal> = {}): AdminPrincipal {
  return {
    provider: "test",
    userId: "admin-1",
    email: "admin@vamo.test",
    role: "admin",
    scopes: ["vamo"],
    assuranceLevel: "aal2",
    mfaRequired: true,
    hasVerifiedMfaFactor: true,
    stepUpSatisfiedAt: FRESH,
    ...overrides
  };
}

function assertBlocked(
  result: { ok: boolean; blocks?: Array<{ code: BatchProductionPackageWaveBlockCode }> },
  code: BatchProductionPackageWaveBlockCode
) {
  assert.equal(result.ok, false);
  if (result.ok) return;
  assert.ok(result.blocks?.some((block) => block.code === code), `expected block ${code}`);
}
