import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { ProductionInboxPackageApplyTelemetry } from "../../adapters/target/src/postgres-production-inbox-telemetry.js";
import {
  buildBatchQueueSnapshotFromItems,
  type BatchQueueItem
} from "../src/batch-queue-read-model.js";
import {
  enrichBatchQueueSnapshotWithApplyTelemetry,
  mapProductionInboxApplyTelemetry
} from "../src/production-package-wave-apply-telemetry.js";

const UNIT_KEY = "vamo-place-intelligence:paris-france:landmark";
const PACKAGE_ID = "batch-production-inbox:plan:wave:42:unit:paris";

function telemetry(
  overrides: Partial<ProductionInboxPackageApplyTelemetry> = {}
): ProductionInboxPackageApplyTelemetry {
  return {
    packageId: PACKAGE_ID,
    shipmentStatus: "production_inbox_delivered",
    checksum: "abc123",
    appliedAt: null,
    itemCount: 2,
    pendingItemCount: 2,
    appliedItemCount: 0,
    skippedItemCount: 0,
    rejectedItemCount: 0,
    latestApplyLogResult: null,
    latestApplyLogDetail: null,
    ...overrides
  };
}

function queueItem(status: BatchQueueItem["status"]): BatchQueueItem {
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
    status,
    blockReasons: [],
    dryRunReport: null
  };
}

function baseSnapshot() {
  return buildBatchQueueSnapshotFromItems({
    planId: "vamo-eu-poi-sample",
    projectKey: "vamo",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    sourceKey: "fsq-os-places-sample",
    safetyMode: "dry_run",
    items: [queueItem("production_package_delivered")],
    latestProductionPackageWave: {
      waveKey: "wave-smoke",
      status: "delivered",
      targetEnvironment: "production",
      targetKey: "vamo-place-intelligence",
      schemaContract: "vamo-place-intelligence@1",
      maxUnits: 1,
      maxRows: 10,
      maxPackages: 1,
      unitCount: 1,
      totalPlannedRows: 2,
      packageId: PACKAGE_ID,
      consumerApplyStatus: "pending",
      items: [
        {
          unitKey: UNIT_KEY,
          runOrder: 1,
          status: "delivered",
          plannedRowCount: 2,
          schemaContract: "vamo-place-intelligence@1",
          packageId: PACKAGE_ID,
          blockers: []
        }
      ]
    }
  });
}

describe("mapProductionInboxApplyTelemetry", () => {
  it("maps pending inbox delivery to consumer_apply_pending", () => {
    const mapped = mapProductionInboxApplyTelemetry(telemetry());
    assert.equal(mapped.consumerApplyStatus, "pending");
    assert.equal(mapped.waveStatus, "consumer_apply_pending");
    assert.equal(mapped.queueItemStatus, "consumer_apply_pending");
  });

  it("maps consumer_applied shipment status to applied states", () => {
    const mapped = mapProductionInboxApplyTelemetry(
      telemetry({
        shipmentStatus: "consumer_applied",
        appliedAt: "2026-07-07T12:00:00.000Z",
        pendingItemCount: 0,
        appliedItemCount: 2
      })
    );
    assert.equal(mapped.consumerApplyStatus, "applied");
    assert.equal(mapped.waveStatus, "consumer_applied");
    assert.equal(mapped.queueItemStatus, "consumer_applied");
  });

  it("maps consumer_apply_failed shipment status to failed states", () => {
    const mapped = mapProductionInboxApplyTelemetry(
      telemetry({
        shipmentStatus: "consumer_apply_failed",
        latestApplyLogResult: "consumer_apply_failed",
        latestApplyLogDetail: "schema mismatch"
      })
    );
    assert.equal(mapped.consumerApplyStatus, "failed");
    assert.equal(mapped.waveStatus, "consumer_apply_failed");
    assert.equal(mapped.queueItemStatus, "consumer_apply_failed");
  });
});

describe("enrichBatchQueueSnapshotWithApplyTelemetry", () => {
  it("enriches snapshot progress counts for applied telemetry", () => {
    const enriched = enrichBatchQueueSnapshotWithApplyTelemetry({
      snapshot: baseSnapshot(),
      telemetryAvailable: true,
      telemetryByPackageId: {
        [PACKAGE_ID]: mapProductionInboxApplyTelemetry(
          telemetry({
            shipmentStatus: "consumer_applied",
            pendingItemCount: 0,
            appliedItemCount: 2
          })
        )
      }
    });
    assert.equal(enriched.latestProductionPackageWave?.status, "consumer_applied");
    assert.equal(enriched.progress.productionPackage.applied, 1);
    assert.equal(enriched.progress.productionPackage.delivered, 0);
    assert.equal(enriched.items[0]?.status, "consumer_applied");
  });

  it("falls back gracefully when telemetry is unavailable", () => {
    const snapshot = baseSnapshot();
    const enriched = enrichBatchQueueSnapshotWithApplyTelemetry({
      snapshot,
      telemetryAvailable: false,
      telemetryByPackageId: {}
    });
    assert.equal(enriched.latestProductionPackageWave?.telemetrySource, "control");
    assert.equal(enriched.progress.productionPackage.delivered, 1);
  });

  it("marks missing inbox packages without changing delivered counts", () => {
    const enriched = enrichBatchQueueSnapshotWithApplyTelemetry({
      snapshot: baseSnapshot(),
      telemetryAvailable: true,
      telemetryByPackageId: {}
    });
    assert.equal(enriched.latestProductionPackageWave?.telemetrySource, "missing");
    assert.equal(enriched.latestProductionPackageWave?.items?.[0]?.telemetrySource, "missing");
    assert.equal(enriched.progress.productionPackage.delivered, 1);
  });
});
