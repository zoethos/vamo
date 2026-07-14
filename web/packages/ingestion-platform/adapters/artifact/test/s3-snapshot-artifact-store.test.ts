import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { describe, it } from "node:test";

import {
  computeSnapshotArtifactBundleSha256,
  deriveSnapshotArtifactKey,
  verifySnapshotArtifactBundleContents
} from "../../../core/src/snapshot-artifact-store.js";
import {
  createS3SnapshotArtifactStore,
  type S3ObjectClientLike
} from "../src/s3-snapshot-artifact-store.js";

function buildSampleArtifacts() {
  const sourceJsonl =
    '{"source_row_id":1,"source":{"id":"fsq_rome_colosseum","name":"Colosseum","latitude":41.8902,"longitude":12.4922},"scope":{"geography":"rome-italy","category":"landmark"},"attribution":"FSQ Open Source Places"}\n';
  const outputSha256 = createHash("sha256").update(sourceJsonl).digest("hex");
  const releaseId = "fsq_os_places-20260701-abc123def456";
  const releaseJson = `${JSON.stringify(
    {
      kind: "ingestion.snapshot_release",
      releaseId,
      sourceKey: "fsq-os-places-snapshot",
      outputSha256,
      intendedConsumer: "vamo",
      intendedTarget: "vamo-place-intelligence"
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

class FakeS3Client implements S3ObjectClientLike {
  readonly objects = new Map<string, string>();

  async headObject(input: { bucket: string; key: string }) {
    return { exists: this.objects.has(`${input.bucket}/${input.key}`) };
  }

  async getObject(input: { bucket: string; key: string }) {
    const value = this.objects.get(`${input.bucket}/${input.key}`);
    if (value === undefined) {
      throw new Error("NoSuchKey");
    }
    return { body: value };
  }

  async putObject(input: {
    bucket: string;
    key: string;
    body: string;
    ifNoneMatch?: string;
  }) {
    const objectId = `${input.bucket}/${input.key}`;
    if (input.ifNoneMatch === "*" && this.objects.has(objectId)) {
      throw new Error("PreconditionFailed");
    }
    if (this.objects.has(objectId)) {
      throw new Error("ObjectAlreadyExists");
    }
    this.objects.set(objectId, input.body);
  }
}

describe("s3 snapshot artifact store", () => {
  it("stores, reads, and verifies immutable bundles without using ETags", async () => {
    const sampleArtifacts = buildSampleArtifacts();
    const artifacts = {
      sourceJsonl: sampleArtifacts.sourceJsonl,
      releaseJson: sampleArtifacts.releaseJson,
      coverageReportJson: sampleArtifacts.coverageReportJson
    };
    const client = new FakeS3Client();
    const store = createS3SnapshotArtifactStore({
      config: {
        kind: "s3",
        bucket: "confluendo-artifacts",
        region: "eu-west-1",
        prefix: "snapshots"
      },
      client
    });
    const artifactKey = deriveSnapshotArtifactKey({
      sourceKey: "fsq-os-places-snapshot",
      releaseId: sampleArtifacts.releaseId,
      outputSha256: sampleArtifacts.outputSha256
    });

    const put = await store.putReleaseBundle({ artifactKey, artifacts });
    assert.equal(put.bundleSha256, computeSnapshotArtifactBundleSha256(artifacts));
    assert.match(put.artifactUri, /^s3:\/\/confluendo-artifacts\//);

    const loaded = await store.readReleaseBundle({ artifactKey });
    assert.equal(verifySnapshotArtifactBundleContents(loaded), true);
    assert.equal(
      await store.verifyReleaseBundle({
        artifactKey,
        expectedBundleSha256: put.bundleSha256
      }),
      true
    );
  });

  it("refuses overwrite of an existing release bundle", async () => {
    const sampleArtifacts = buildSampleArtifacts();
    const artifacts = {
      sourceJsonl: sampleArtifacts.sourceJsonl,
      releaseJson: sampleArtifacts.releaseJson,
      coverageReportJson: sampleArtifacts.coverageReportJson
    };
    const client = new FakeS3Client();
    const store = createS3SnapshotArtifactStore({
      config: { kind: "s3", bucket: "confluendo-artifacts", region: "eu-west-1" },
      client
    });
    const artifactKey = deriveSnapshotArtifactKey({
      sourceKey: "fsq-os-places-snapshot",
      releaseId: sampleArtifacts.releaseId,
      outputSha256: sampleArtifacts.outputSha256
    });

    await store.putReleaseBundle({ artifactKey, artifacts });
    await assert.rejects(() => store.putReleaseBundle({ artifactKey, artifacts }), /already_exists/);
  });

  it("rejects unsafe artifact keys and detects bundle SHA drift", async () => {
    const client = new FakeS3Client();
    const store = createS3SnapshotArtifactStore({
      config: { kind: "s3", bucket: "confluendo-artifacts", region: "eu-west-1" },
      client
    });
    const sampleArtifacts = buildSampleArtifacts();
    const artifacts = {
      sourceJsonl: sampleArtifacts.sourceJsonl,
      releaseJson: sampleArtifacts.releaseJson,
      coverageReportJson: sampleArtifacts.coverageReportJson
    };
    await assert.rejects(
      () =>
        store.putReleaseBundle({
          artifactKey: "../escape/key/sha",
          artifacts
        }),
      /artifact_key_unsafe/
    );

    const artifactKey = deriveSnapshotArtifactKey({
      sourceKey: "fsq-os-places-snapshot",
      releaseId: sampleArtifacts.releaseId,
      outputSha256: sampleArtifacts.outputSha256
    });
    await store.putReleaseBundle({ artifactKey, artifacts });
    assert.equal(
      await store.verifyReleaseBundle({
        artifactKey,
        expectedBundleSha256: "f".repeat(64)
      }),
      false
    );
  });
});
