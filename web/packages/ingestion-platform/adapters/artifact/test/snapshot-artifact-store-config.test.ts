import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  LEGACY_LOCAL_ARTIFACT_STORE_DIR_ENV,
  SNAPSHOT_ARTIFACT_S3_BUCKET_ENV,
  SNAPSHOT_ARTIFACT_S3_REGION_ENV,
  SNAPSHOT_ARTIFACT_STORE_KIND_ENV,
  parseSnapshotArtifactStoreConfig
} from "../src/snapshot-artifact-store-config.js";

describe("snapshot artifact store config", () => {
  it("prefers explicit local directory over hosted S3 env", () => {
    const parsed = parseSnapshotArtifactStoreConfig({
      env: {
        [SNAPSHOT_ARTIFACT_STORE_KIND_ENV]: "s3",
        [SNAPSHOT_ARTIFACT_S3_BUCKET_ENV]: "confluendo-artifacts",
        [SNAPSHOT_ARTIFACT_S3_REGION_ENV]: "eu-west-1"
      },
      preferLocalDir: "/tmp/local-artifacts"
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.config.kind, "local");
    assert.equal(parsed.config.baseDir, "/tmp/local-artifacts");
  });

  it("parses hosted S3 configuration from server env", () => {
    const parsed = parseSnapshotArtifactStoreConfig({
      env: {
        [SNAPSHOT_ARTIFACT_STORE_KIND_ENV]: "s3",
        [SNAPSHOT_ARTIFACT_S3_BUCKET_ENV]: "confluendo-artifacts",
        [SNAPSHOT_ARTIFACT_S3_REGION_ENV]: "eu-west-1",
        CONFLUENDO_SNAPSHOT_ARTIFACT_S3_PREFIX: "snapshots/"
      }
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.config.kind, "s3");
    assert.equal(parsed.config.bucket, "confluendo-artifacts");
    assert.equal(parsed.config.region, "eu-west-1");
    assert.equal(parsed.config.prefix, "snapshots");
  });

  it("falls back to legacy local directory env", () => {
    const parsed = parseSnapshotArtifactStoreConfig({
      env: {
        [LEGACY_LOCAL_ARTIFACT_STORE_DIR_ENV]: "/secure/local-artifacts"
      }
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.config.kind, "local");
  });

  it("requires hosted S3 config for hosted job contexts", () => {
    const parsed = parseSnapshotArtifactStoreConfig({
      env: {
        [LEGACY_LOCAL_ARTIFACT_STORE_DIR_ENV]: "/secure/local-artifacts"
      },
      requireHostedStore: true
    });
    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.equal(parsed.blocks[0]?.code, "hosted_artifact_store_missing");
  });
});
