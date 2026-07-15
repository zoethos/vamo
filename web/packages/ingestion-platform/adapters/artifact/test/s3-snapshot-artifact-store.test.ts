import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { describe, it } from "node:test";

import {
  computeSnapshotArtifactBundleSha256,
  deriveSnapshotArtifactKey
} from "../../../core/src/snapshot-artifact-store.js";
import { isSnapshotArtifactStorageError } from "../../../core/src/snapshot-artifact-storage-error.js";
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

  async headBucket() {}

  async headObject(input: { bucket: string; key: string }) {
    return { exists: this.objects.has(`${input.bucket}/${input.key}`) };
  }

  async getObject(input: { bucket: string; key: string }) {
    const value = this.objects.get(`${input.bucket}/${input.key}`);
    if (value === undefined) {
      const error = new Error("NoSuchKey");
      error.name = "NoSuchKey";
      throw error;
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
      const error = new Error("PreconditionFailed");
      error.name = "PreconditionFailed";
      throw error;
    }
    this.objects.set(objectId, input.body);
  }
}

class PartialUploadFakeS3Client extends FakeS3Client {
  private readonly failKey: string;
  private failedOnce = false;

  constructor(failKey: string) {
    super();
    this.failKey = failKey;
  }

  override async putObject(input: {
    bucket: string;
    key: string;
    body: string;
    ifNoneMatch?: string;
  }) {
    const objectId = `${input.bucket}/${input.key}`;
    if (!this.failedOnce && objectId === this.failKey) {
      this.failedOnce = true;
      throw new Error("NetworkFailure");
    }
    return super.putObject(input);
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
    assert.equal(
      await store.verifyReleaseBundle({
        artifactKey,
        expectedBundleSha256: put.bundleSha256
      }),
      true
    );
    assert.equal(loaded.sourceJsonl, artifacts.sourceJsonl);
  });

  it("accepts idempotent retries with identical bundle content", async () => {
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

    const first = await store.putReleaseBundle({ artifactKey, artifacts });
    const second = await store.putReleaseBundle({ artifactKey, artifacts });
    assert.equal(second.bundleSha256, first.bundleSha256);
  });

  it("resumes partial uploads on exact retry and refuses mismatched content", async () => {
    const sampleArtifacts = buildSampleArtifacts();
    const artifacts = {
      sourceJsonl: sampleArtifacts.sourceJsonl,
      releaseJson: sampleArtifacts.releaseJson,
      coverageReportJson: sampleArtifacts.coverageReportJson
    };
    const artifactKey = deriveSnapshotArtifactKey({
      sourceKey: "fsq-os-places-snapshot",
      releaseId: sampleArtifacts.releaseId,
      outputSha256: sampleArtifacts.outputSha256
    });
    const failKey = `confluendo-artifacts/${artifactKey}/release.json`;
    const client = new PartialUploadFakeS3Client(failKey);
    const store = createS3SnapshotArtifactStore({
      config: { kind: "s3", bucket: "confluendo-artifacts", region: "eu-west-1" },
      client
    });

    await assert.rejects(() => store.putReleaseBundle({ artifactKey, artifacts }), /NetworkFailure/);
    await assert.rejects(() => store.readReleaseBundle({ artifactKey }), (error: unknown) =>
      isSnapshotArtifactStorageError(error) && error.code === "artifact_bundle_incomplete"
    );

    const resumed = await store.putReleaseBundle({ artifactKey, artifacts });
    assert.equal(resumed.bundleSha256, computeSnapshotArtifactBundleSha256(artifacts));

    await assert.rejects(
      () =>
        store.putReleaseBundle({
          artifactKey,
          artifacts: {
            ...artifacts,
            releaseJson: `${artifacts.releaseJson}changed`
          }
        }),
      (error: unknown) =>
        isSnapshotArtifactStorageError(error) && error.code === "artifact_bundle_conflict"
    );
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
      (error: unknown) =>
        isSnapshotArtifactStorageError(error) && error.code === "artifact_key_unsafe"
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

  it("distinguishes missing bundles from access and network failures", async () => {
    const client = new FakeS3Client();
    const store = createS3SnapshotArtifactStore({
      config: { kind: "s3", bucket: "confluendo-artifacts", region: "eu-west-1" },
      client
    });
    const artifactKey = deriveSnapshotArtifactKey({
      sourceKey: "fsq-os-places-snapshot",
      releaseId: "fsq_os_places-20260701-abc123def456",
      outputSha256: "abc123"
    });

    await assert.rejects(() => store.readReleaseBundle({ artifactKey }), (error: unknown) =>
      isSnapshotArtifactStorageError(error) && error.code === "artifact_bundle_missing"
    );

    const deniedClient: S3ObjectClientLike = {
      async headBucket() {},
      async headObject() {
        return { exists: false };
      },
      async getObject() {
        const error = new Error("AccessDenied");
        error.name = "AccessDenied";
        throw error;
      },
      async putObject() {
        throw new Error("unexpected put");
      }
    };
    const deniedStore = createS3SnapshotArtifactStore({
      config: { kind: "s3", bucket: "confluendo-artifacts", region: "eu-west-1" },
      client: deniedClient
    });
    await assert.rejects(() => deniedStore.readReleaseBundle({ artifactKey }), (error: unknown) =>
      isSnapshotArtifactStorageError(error) && error.code === "artifact_storage_access_denied"
    );

    const unavailableClient: S3ObjectClientLike = {
      async headBucket() {},
      async headObject() {
        return { exists: false };
      },
      async getObject() {
        throw new Error("NetworkingError");
      },
      async putObject() {
        throw new Error("unexpected put");
      }
    };
    const unavailableStore = createS3SnapshotArtifactStore({
      config: { kind: "s3", bucket: "confluendo-artifacts", region: "eu-west-1" },
      client: unavailableClient
    });
    await assert.rejects(() => unavailableStore.readReleaseBundle({ artifactKey }), (error: unknown) =>
      isSnapshotArtifactStorageError(error) && error.code === "artifact_storage_unavailable"
    );
  });
});
