import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import {
  computeSnapshotArtifactBundleSha256,
  createLocalSnapshotArtifactStore,
  deriveSnapshotArtifactKey,
  SNAPSHOT_ARTIFACT_BUNDLE_FILES,
  verifySnapshotArtifactBundleContents
} from "../src/snapshot-artifact-store.js";

function buildSampleArtifacts() {
  const sourceJsonl =
    '{"source_row_id":1,"source":{"id":"fsq_rome_colosseum","name":"Colosseum","latitude":41.8902,"longitude":12.4922},"scope":{"geography":"rome-italy","category":"landmark"},"attribution":"FSQ Open Source Places"}\n';
  const outputSha256 = createHash("sha256").update(sourceJsonl).digest("hex");
  const releaseId = "fsq_os_places-20260701-abc123def456";
  const releaseJson = `${JSON.stringify(
    {
      kind: "ingestion.snapshot_release",
      releaseId,
      outputSha256
    },
    null,
    2
  )}\n`;
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
      byPoiType: { landmark: 1 }
    },
    null,
    2
  )}\n`;
  return { sourceJsonl, releaseJson, coverageReportJson, outputSha256, releaseId };
}

describe("snapshot artifact store", () => {
  it("derives immutable artifact keys from source, release, and output checksum", () => {
    const key = deriveSnapshotArtifactKey({
      sourceKey: "fsq-os-places-snapshot",
      releaseId: "fsq_os_places-20260701-abc123def456",
      outputSha256: "abc123"
    });
    assert.equal(key, "fsq-os-places-snapshot/fsq_os_places-20260701-abc123def456/abc123");
  });

  it("stores and verifies bundle checksums locally", async () => {
    const sampleArtifacts = buildSampleArtifacts();
    const artifacts = {
      sourceJsonl: sampleArtifacts.sourceJsonl,
      releaseJson: sampleArtifacts.releaseJson,
      coverageReportJson: sampleArtifacts.coverageReportJson
    };
    const baseDir = mkdtempSync(join(tmpdir(), "snapshot-artifact-store-"));
    try {
      const store = createLocalSnapshotArtifactStore(baseDir);
      const artifactKey = deriveSnapshotArtifactKey({
        sourceKey: "fsq-os-places-snapshot",
        releaseId: sampleArtifacts.releaseId,
        outputSha256: sampleArtifacts.outputSha256
      });
      const put = await store.putReleaseBundle({ artifactKey, artifacts });
      assert.equal(put.artifactKey, artifactKey);
      assert.match(put.artifactUri, /^file:\/\//);

      const expectedBundleSha256 = computeSnapshotArtifactBundleSha256(artifacts);
      assert.equal(put.bundleSha256, expectedBundleSha256);
      assert.equal(
        await store.verifyReleaseBundle({
          artifactKey,
          expectedBundleSha256
        }),
        true
      );

      const loaded = await store.readReleaseBundle({ artifactKey });
      for (const fileName of SNAPSHOT_ARTIFACT_BUNDLE_FILES) {
        const field =
          fileName === "source.jsonl"
            ? "sourceJsonl"
            : fileName === "release.json"
              ? "releaseJson"
              : "coverageReportJson";
        assert.equal(loaded[field], artifacts[field]);
        assert.equal(
          readFileSync(join(baseDir, ...artifactKey.split("/"), fileName), "utf8"),
          artifacts[field]
        );
      }
      assert.equal(verifySnapshotArtifactBundleContents(loaded), true);
    } finally {
      rmSync(baseDir, { recursive: true, force: true });
    }
  });
});
