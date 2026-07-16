import assert from "node:assert/strict";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { mkdtempSync } from "node:fs";
import { describe, it } from "node:test";

import { enrichProductionPackageWaveApprovalPlanWithStagedContentHashes } from "../src/batch-production-package-wave-approval-content.js";
import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { buildBatchQueueSnapshotFromItems, sampleVamoEuPoiBatchQueueSnapshot } from "../src/batch-queue-read-model.js";
import {
  BATCH_SNAPSHOT_EMPTY_BLOCK_REASON,
  readSnapshotSourceRowsFromSpec
} from "../src/batch-snapshot-supply-preview.js";
import { buildFullDataBoundBatchQueueSnapshot } from "../src/batch-supply-ready-proposal-binding.js";
import {
  createLocalSnapshotArtifactStore,
  deriveSnapshotArtifactKey
} from "../src/snapshot-artifact-store.js";
import {
  isSourceReconcilableQueueItem,
  reconcileActivatedSnapshotQueue
} from "../src/snapshot-release-activation-reconcile.js";
import { verifySnapshotActivationArtifact } from "../src/snapshot-release-activation-artifact.js";
import { sha256Hex } from "../src/versioned-snapshot-intake.js";

const fullDataPath = "fixtures/platform/ip18/vamo-eu-full-data-batch.yaml";
const consoleDataModule = readFileSync(
  "../../apps/confluendo-console/lib/ip18-batch-queue-data.ts",
  "utf8"
);
const bindingReadModule = readFileSync(
  "core/src/snapshot-release-plan-binding-read.ts",
  "utf8"
);
const approvalRouteModule = readFileSync(
  "../../apps/confluendo-console/app/api/admin/ingestion/production-package-wave/approve/route.ts",
  "utf8"
);

describe("snapshot release activation reconcile", () => {
  it("promotes parked empty scopes when coverage appears", () => {
    const spec = loadFullDataSpec();
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const emptySnapshot = buildFullDataBoundBatchQueueSnapshot({ spec, rows: [] }).snapshot;
    const reconciled = reconcileActivatedSnapshotQueue({
      currentSnapshot: emptySnapshot,
      spec,
      rows
    });

    assert.ok(reconciled.supplyReadyCount > 0);
    assert.ok(reconciled.changedUnitKeys.length > 0);
    assert.ok(
      reconciled.snapshot.items.some(
        (item) => item.status === "ready_for_dry_run" && item.proposal !== null
      )
    );
  });

  it("blocks source-ready scopes and clears proposals when coverage disappears", () => {
    const spec = loadFullDataSpec();
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const readySnapshot = buildFullDataBoundBatchQueueSnapshot({ spec, rows }).snapshot;
    const romeKey = "vamo-place-intelligence:rome-italy:poi";
    const rowsWithoutRome = rows.filter(
      (row) => row.scope?.geography !== "rome-italy" || row.scope?.category !== "poi"
    );

    const reconciled = reconcileActivatedSnapshotQueue({
      currentSnapshot: readySnapshot,
      spec,
      rows: rowsWithoutRome
    });

    const rome = reconciled.snapshot.items.find((item) => item.unitKey === romeKey);
    assert.ok(rome);
    assert.equal(rome.status, "blocked");
    assert.equal(rome.proposal, null);
    assert.ok(rome.blockReasons.includes(BATCH_SNAPSHOT_EMPTY_BLOCK_REASON));
    assert.ok(reconciled.changedUnitKeys.includes(romeKey));
  });

  it("preserves consumer_applied and staging-verified rows unchanged", () => {
    const spec = loadFullDataSpec();
    const rows = readSnapshotSourceRowsFromSpec(spec)!;
    const base = buildFullDataBoundBatchQueueSnapshot({ spec, rows }).snapshot;
    const preservedKey = base.items[0]!.unitKey;
    const items = base.items.map((item, index) => {
      if (index === 0) {
        return {
          ...item,
          status: "consumer_applied" as const,
          dryRunReport: {
            wroteToTarget: false as const,
            rowsProcessed: 2,
            insertCount: 2,
            updateCount: 0,
            noOpCount: 0,
            executionKey: "dry-run:preserved"
          }
        };
      }
      if (index === 1) {
        return {
          ...item,
          status: "staging_canary_succeeded" as const,
          dryRunReport: {
            wroteToTarget: false as const,
            rowsProcessed: 2,
            insertCount: 2,
            updateCount: 0,
            noOpCount: 0,
            executionKey: "dry-run:staging"
          }
        };
      }
      return item;
    });

    const currentSnapshot = buildBatchQueueSnapshotFromItems({
      planId: base.planId,
      projectKey: base.projectKey,
      targetKey: base.targetKey,
      targetEnvironment: base.targetEnvironment,
      sourceKey: base.sourceKey,
      safetyMode: base.safetyMode,
      items,
      planNextAction: base.nextAction
    });

    const reconciled = reconcileActivatedSnapshotQueue({
      currentSnapshot,
      spec,
      rows: []
    });

    const preserved = reconciled.snapshot.items.find((item) => item.unitKey === preservedKey);
    assert.equal(preserved?.status, "consumer_applied");
    assert.equal(reconciled.changedUnitKeys.includes(preservedKey), false);
    assert.equal(reconciled.preservedCount >= 2, true);
    assert.equal(isSourceReconcilableQueueItem(items[0]!), false);
  });
});

describe("snapshot release activation artifact verification", () => {
  it("blocks control mutation path when the activated bundle drifts", async () => {
    const storeDir = mkdtempSync(join(tmpdir(), "snapshot-activation-artifact-"));
    try {
      const { release, artifactKey, bundleSha256 } = await writeVerifiedArtifactBundle(storeDir);
      const spec = loadFullDataSpec();
      const verified = await verifySnapshotActivationArtifact({
        release,
        plan: spec,
        artifactStoreDir: storeDir,
        expectedBundleSha256: bundleSha256
      });
      assert.equal(verified.ok, true);

      const artifactDir = join(storeDir, ...artifactKey.split("/"));
      writeFileSync(
        join(artifactDir, "coverage-report.json"),
        JSON.stringify({
          kind: "ingestion.snapshot_coverage_report",
          releaseId: release.releaseId,
          validRowCount: 999,
          invalidRowCount: 0,
          duplicateRowCount: 0,
          outOfScopeRowCount: 0
        }),
        "utf8"
      );

      const blocked = await verifySnapshotActivationArtifact({
        release,
        plan: spec,
        artifactStoreDir: storeDir,
        expectedBundleSha256: bundleSha256
      });
      assert.equal(blocked.ok, false);
      if (blocked.ok) {
        throw new Error("expected checksum mismatch");
      }
      assert.ok(blocked.blocks.includes("artifact_bundle_checksum_mismatch"));
    } finally {
      rmSync(storeDir, { recursive: true, force: true });
    }
  });
});

describe("active-release production approval content", () => {
  it("fails closed when staged hash evidence is missing for active-release plans", async () => {
    const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
    const unit = {
      ...snapshot.items[0]!,
      status: "staging_canary_succeeded" as const,
      dryRunReport: {
        wroteToTarget: false as const,
        rowsProcessed: 2,
        insertCount: 2,
        updateCount: 0,
        noOpCount: 0,
        executionKey: "dry-run:approval-hash"
      }
    };
    await assert.rejects(
      () =>
        enrichProductionPackageWaveApprovalPlanWithStagedContentHashes({
          plan: {
            selectedUnits: [
              {
                item: unit,
                stagingEvidence: { status: "succeeded" }
              }
            ]
          } as Parameters<typeof enrichProductionPackageWaveApprovalPlanWithStagedContentHashes>[0]["plan"],
          queueItemsByUnitKey: { [unit.unitKey]: unit },
          loadCandidates: async () => [],
          useRecordedStagingHashes: true,
          stagingEvidenceByUnitKey: {
            [unit.unitKey]: { status: "succeeded" }
          }
        }),
      /staged content hash evidence is missing/
    );
  });
});

describe("snapshot release browser boundary", () => {
  it("does not expose artifact URIs, artifact roots, or control DSNs in console read paths", () => {
    assert.doesNotMatch(consoleDataModule, /file:\/\//);
    assert.doesNotMatch(consoleDataModule, /INGESTION_ARTIFACT_STORE_DIR/);
    assert.doesNotMatch(bindingReadModule, /artifactUri/);
    assert.doesNotMatch(bindingReadModule, /artifact_key/);
    assert.doesNotMatch(bindingReadModule, /file:\/\//);
    assert.doesNotMatch(approvalRouteModule, /INGESTION_ARTIFACT_STORE_DIR/);
    assert.doesNotMatch(approvalRouteModule, /file:\/\//);
  });

  it("keeps legacy sample queue path when control database is unavailable", () => {
    assert.match(consoleDataModule, /if \(!controlDb\)/);
    assert.match(consoleDataModule, /return sample\(\)/);
    assert.match(consoleDataModule, /sampleVamoEuPoiBatchQueueSnapshot/);
  });

  it("forbids bundled fixture fallback when an active binding requires artifact store", () => {
    const source = readFileSync("core/src/activated-snapshot-candidate-loader.ts", "utf8");
    assert.match(source, /bundled fixture fallback is forbidden/);
  });
});

async function writeVerifiedArtifactBundle(storeDir: string) {
  const spec = loadFullDataSpec();
  const rows = readSnapshotSourceRowsFromSpec(spec)!;
  const sourceJsonl = rows.map((row) => JSON.stringify(row)).join("\n") + "\n";
  const outputSha256 = sha256Hex(sourceJsonl);
  const releaseId = "fsq_os_places-20260702-testactivation";
  const artifactKey = deriveSnapshotArtifactKey({
    sourceKey: spec.sourceKey,
    releaseId,
    outputSha256
  });
  const releaseJson = JSON.stringify({
    releaseId,
    sourceKey: spec.sourceKey,
    outputSha256,
    intendedConsumer: spec.projectKey,
    intendedTarget: spec.targetKey
  });
  const coverageReportJson = JSON.stringify({
    kind: "ingestion.snapshot_coverage_report",
    releaseId,
    derivedFromValidRowsOnly: true,
    validRowCount: rows.length,
    invalidRowCount: 0,
    duplicateRowCount: 0,
    outOfScopeRowCount: 0,
    byCountry: {},
    byPoiType: {},
    byCountryAndPoiType: {}
  });
  const store = createLocalSnapshotArtifactStore(storeDir);
  const stored = await store.putReleaseBundle({
    artifactKey,
    artifacts: { sourceJsonl, releaseJson, coverageReportJson }
  });
  const coverage = {
    kind: "ingestion.snapshot_coverage_report" as const,
    releaseId,
    derivedFromValidRowsOnly: true as const,
    validRowCount: rows.length,
    invalidRowCount: 0,
    duplicateRowCount: 0,
    outOfScopeRowCount: 0,
    byCountry: {},
    byPoiType: {},
    byCountryAndPoiType: {}
  };
  return {
    artifactKey,
    bundleSha256: stored.bundleSha256,
    release: {
      releaseId,
      sourceKey: spec.sourceKey,
      outputSha256,
      intendedConsumer: spec.projectKey,
      intendedTarget: spec.targetKey,
      artifactKey,
      coverage
    }
  };
}

function loadFullDataSpec() {
  const parsed = parseBatchPlanSpec(readFileSync(fullDataPath, "utf8"));
  assert.equal(parsed.ok, true);
  if (!parsed.ok) {
    throw new Error("full-data plan failed to parse");
  }
  return parsed.spec;
}
