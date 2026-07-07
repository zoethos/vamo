import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { evaluateBatchProductionPackageWaveDelivery } from "../src/batch-production-package-wave-delivery-policy.js";
import type { LoadedProductionPackageWave } from "../src/batch-production-package-wave-load.js";
import type { BatchQueueItem } from "../src/batch-queue-read-model.js";
import { VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT } from "../src/batch-production-package-wave-policy.js";

const NOW = "2026-07-07T10:00:00.000Z";
const UNIT_KEY = "vamo-place-intelligence:paris-france:landmark";

function queueItem(overrides: Partial<BatchQueueItem> = {}): BatchQueueItem {
  return {
    unitKey: UNIT_KEY,
    runOrder: 1,
    geography: "paris-france",
    geographyKind: "city",
    country: "france",
    category: "landmark",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    sourceKey: "fsq-os-places-sample",
    priority: 8,
    status: "production_package_approved",
    blockReasons: [],
    dryRunReport: {
      wroteToTarget: false,
      rowsProcessed: 2,
      insertCount: 2,
      updateCount: 0,
      noOpCount: 0,
      executionKey: "dry-run:policy"
    },
    ...overrides
  };
}

function loadedWave(overrides: Partial<LoadedProductionPackageWave> = {}): LoadedProductionPackageWave {
  return {
    id: "wave-1",
    waveKey: "batch-production-inbox:plan:wave:audit:unit:paris",
    batchPlanId: "plan-1",
    planKey: "vamo-eu-poi-sample",
    projectKey: "vamo",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "production",
    schemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
    maxUnits: 1,
    maxRows: 10,
    maxPackages: 1,
    status: "approved",
    auditReason: "Approve smoke wave.",
    approvalAuditId: "42",
    approvedAt: NOW,
    approvalExpiresAt: "2026-07-07T10:15:00.000Z",
    approvedBy: { email: "admin@vamo.test" },
    packageId: null,
    packageChecksum: null,
    deliveryAuditId: null,
    summary: {},
    items: [
      {
        id: "item-1",
        unitKey: UNIT_KEY,
        runOrder: 1,
        status: "approved",
        plannedRowCount: 2,
        packageKey: `batch-production-inbox:vamo-eu-poi-sample:wave:42:unit:${UNIT_KEY}`,
        packageId: null,
        checksum: null,
        dryRunEvidence: {
          wroteToTarget: false,
          insertCount: 2,
          updateCount: 0,
          queueItemStatusAtApproval: "staging_canary_succeeded"
        },
        stagingEvidence: { status: "succeeded", shipmentKey: "staging:smoke" },
        queueItemId: "queue-1",
        blockers: []
      }
    ],
    ...overrides
  };
}

describe("evaluateBatchProductionPackageWaveDelivery", () => {
  it("accepts an approved wave within bounds", () => {
    const result = evaluateBatchProductionPackageWaveDelivery({
      projectKey: "vamo",
      targetEnvironment: "production",
      wave: loadedWave(),
      queueItemsByUnitKey: { [UNIT_KEY]: queueItem() },
      stagingEvidenceByUnitKey: {
        [UNIT_KEY]: { status: "succeeded", shipmentKey: "staging:smoke" }
      },
      now: NOW
    });
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.plan.pendingUnitKeys.length, 1);
    assert.match(result.plan.unitPlans[0]?.packageKey ?? "", /batch-production-inbox:/);
  });

  it("blocks expired wave status", () => {
    const result = evaluateBatchProductionPackageWaveDelivery({
      projectKey: "vamo",
      targetEnvironment: "production",
      wave: loadedWave({ status: "expired" }),
      queueItemsByUnitKey: { [UNIT_KEY]: queueItem() },
      now: NOW
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.blocks[0]?.code, "approval_expired");
  });

  it("blocks stale approval freshness", () => {
    const result = evaluateBatchProductionPackageWaveDelivery({
      projectKey: "vamo",
      targetEnvironment: "production",
      wave: loadedWave({
        approvedAt: "2026-07-07T09:00:00.000Z",
        approvalExpiresAt: "2026-07-07T09:15:00.000Z"
      }),
      queueItemsByUnitKey: { [UNIT_KEY]: queueItem() },
      now: "2026-07-07T10:00:00.000Z"
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.blocks.some((block) => block.code === "approval_expired"), true);
  });

  it("blocks non-production target environment", () => {
    const result = evaluateBatchProductionPackageWaveDelivery({
      projectKey: "vamo",
      targetEnvironment: "staging",
      wave: loadedWave(),
      queueItemsByUnitKey: { [UNIT_KEY]: queueItem() },
      now: NOW
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.blocks[0]?.code, "not_production_environment");
  });

  it("blocks overrides above approved bounds", () => {
    const result = evaluateBatchProductionPackageWaveDelivery({
      projectKey: "vamo",
      targetEnvironment: "production",
      wave: loadedWave(),
      queueItemsByUnitKey: { [UNIT_KEY]: queueItem() },
      maxUnits: 2,
      now: NOW
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.blocks[0]?.code, "approved_wave_bounds_exceeded");
  });

  it("blocks queue drift before delivery", () => {
    const result = evaluateBatchProductionPackageWaveDelivery({
      projectKey: "vamo",
      targetEnvironment: "production",
      wave: loadedWave(),
      queueItemsByUnitKey: {
        [UNIT_KEY]: queueItem({
          dryRunReport: {
            wroteToTarget: false,
            rowsProcessed: 2,
            insertCount: 1,
            updateCount: 0,
            noOpCount: 0
          }
        })
      },
      now: NOW
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.blocks.some((block) => block.code === "dry_run_evidence_drift"), true);
  });
});
