import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { buildBatchQueueSnapshotFromItems, type BatchQueueItem } from "../src/batch-queue-read-model.js";
import {
  PRODUCTION_PACKAGE_WAVE_BLOCK_LABELS,
  describeProductionPackageWaveStatus,
  summarizeProductionPackageWaveDashboard
} from "../src/production-package-wave-dashboard.js";

describe("production package-wave dashboard helpers", () => {
  it("renders eligible unit count from staging evidence", () => {
    const snapshot = snapshotWithItems([stagingProvenItem("unit-a")]);
    const summary = summarizeProductionPackageWaveDashboard({
      snapshot,
      targetKey: "vamo-place-intelligence",
      stagingEvidenceByUnitKey: {
        "unit-a": { status: "succeeded", shipmentKey: "staging:unit-a" }
      }
    });
    assert.equal(summary.eligibleCount, 1);
    assert.equal(summary.progress.ready, 0);
  });

  it("renders block code labels for policy failures", () => {
    assert.match(PRODUCTION_PACKAGE_WAVE_BLOCK_LABELS.dry_run_invariant_violated, /wroteToTarget=false/);
    assert.match(PRODUCTION_PACKAGE_WAVE_BLOCK_LABELS.role_denied, /admin/);
  });

  it("distinguishes consumer apply failed from delivered", () => {
    const failed = describeProductionPackageWaveStatus("consumer_apply_failed");
    const delivered = describeProductionPackageWaveStatus("production_package_delivered");
    assert.equal(failed.tone, "danger");
    assert.equal(delivered.tone, "good");
    assert.notEqual(failed.label, delivered.label);
    assert.match(failed.detail ?? "", /not the same as already delivered/i);
  });

  it("renders latest package wave expiry in summary", () => {
    const snapshot = snapshotWithItems([stagingProvenItem("unit-a")]);
    const summary = summarizeProductionPackageWaveDashboard({
      snapshot,
      targetKey: "vamo-place-intelligence",
      stagingEvidenceByUnitKey: {
        "unit-a": { status: "succeeded" }
      },
      latestWave: {
        waveKey: "batch-production-inbox:plan:wave:13:unit:unit-a",
        status: "approved",
        targetEnvironment: "production",
        targetKey: "vamo-place-intelligence",
        schemaContract: "vamo-place-intelligence@1",
        maxUnits: 1,
        maxRows: 10,
        maxPackages: 1,
        unitCount: 1,
        totalPlannedRows: 2,
        approvalExpiresAt: "2026-07-07T10:15:00.000Z"
      }
    });
    assert.equal(summary.latestWaveStatus?.label, "Wave approved (control plane)");
  });
});

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

function stagingProvenItem(unitKey: string): BatchQueueItem {
  return {
    unitKey,
    runOrder: 1,
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
      rowsProcessed: 2,
      insertCount: 2,
      updateCount: 0,
      noOpCount: 0
    }
  };
}
