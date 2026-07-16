import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, it } from "node:test";

import { materializeArtifactBundleToScopedDir } from "../src/snapshot-artifact-materialize.js";
import { createLocalSnapshotArtifactStore, deriveSnapshotArtifactKey } from "../src/snapshot-artifact-store.js";

function buildSampleArtifacts() {
  const sourceJsonl =
    '{"source_row_id":1,"source":{"id":"fsq_rome_colosseum","name":"Colosseum","latitude":41.8902,"longitude":12.4922},"scope":{"geography":"rome-italy","category":"landmark"},"attribution":"FSQ Open Source Places"}\n';
  const outputSha256 = createHash("sha256").update(sourceJsonl).digest("hex");
  const releaseId = "fsq_os_places-20260701-abc123def456";
  const releaseJson = `${JSON.stringify({ kind: "ingestion.snapshot_release", releaseId, outputSha256 }, null, 2)}\n`;
  const coverageReportJson = `${JSON.stringify(
    {
      kind: "ingestion.snapshot_coverage_report",
      releaseId,
      derivedFromValidRowsOnly: true,
      validRowCount: 1,
      invalidRowCount: 0,
      duplicateRowCount: 0,
      outOfScopeRowCount: 0,
      byCountry: { italy: 1 },
      byPoiType: { landmark: 1 },
      byCountryAndPoiType: { italy: { landmark: 1 } }
    },
    null,
    2
  )}\n`;
  return { sourceJsonl, releaseJson, coverageReportJson, outputSha256, releaseId };
}

describe("snapshot artifact materialize", () => {
  it("cleans up temp materialization after successful dispose", async () => {
    const sampleArtifacts = buildSampleArtifacts();
    const baseDir = mkdtempSync(join(tmpdir(), "snapshot-artifact-materialize-"));
    const store = createLocalSnapshotArtifactStore(baseDir);
    const artifactKey = deriveSnapshotArtifactKey({
      sourceKey: "fsq-os-places-snapshot",
      releaseId: sampleArtifacts.releaseId,
      outputSha256: sampleArtifacts.outputSha256
    });
    await store.putReleaseBundle({
      artifactKey,
      artifacts: {
        sourceJsonl: sampleArtifacts.sourceJsonl,
        releaseJson: sampleArtifacts.releaseJson,
        coverageReportJson: sampleArtifacts.coverageReportJson
      }
    });

    const materialized = await materializeArtifactBundleToScopedDir({ store, artifactKey });
    const tempRoot = dirname(dirname(dirname(materialized.artifactDir)));
    assert.equal(existsSync(materialized.artifactDir), true);
    await materialized.dispose();
    assert.equal(existsSync(materialized.artifactDir), false);
    assert.equal(existsSync(tempRoot), false);
    assert.equal(existsSync(baseDir), true);
  });

  it("cleans up temp materialization when execution fails after materialize", async () => {
    const sampleArtifacts = buildSampleArtifacts();
    const baseDir = mkdtempSync(join(tmpdir(), "snapshot-artifact-materialize-"));
    const store = createLocalSnapshotArtifactStore(baseDir);
    const artifactKey = deriveSnapshotArtifactKey({
      sourceKey: "fsq-os-places-snapshot",
      releaseId: sampleArtifacts.releaseId,
      outputSha256: sampleArtifacts.outputSha256
    });
    await store.putReleaseBundle({
      artifactKey,
      artifacts: {
        sourceJsonl: sampleArtifacts.sourceJsonl,
        releaseJson: sampleArtifacts.releaseJson,
        coverageReportJson: sampleArtifacts.coverageReportJson
      }
    });

    const materialized = await materializeArtifactBundleToScopedDir({ store, artifactKey });
    const tempRoot = dirname(dirname(dirname(materialized.artifactDir)));
    try {
      throw new Error("simulated execution failure");
    } catch {
      await materialized.dispose();
      assert.equal(existsSync(tempRoot), false);
      assert.equal(existsSync(baseDir), true);
    }
  });
});
