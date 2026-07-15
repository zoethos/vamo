import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  LEGACY_LOCAL_ARTIFACT_STORE_DIR_ENV,
  SNAPSHOT_ARTIFACT_S3_BUCKET_ENV,
  SNAPSHOT_ARTIFACT_S3_REGION_ENV,
  SNAPSHOT_ARTIFACT_STORE_KIND_ENV,
  SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID_ENV,
  SNAPSHOT_ARTIFACT_SUPABASE_BUCKET_ENV,
  SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF_ENV,
  SNAPSHOT_ARTIFACT_SUPABASE_REGION_ENV,
  SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY_ENV,
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
    assert.equal(parsed.config.provider, "generic_s3");
  });

  it("normalizes a Supabase Storage profile into the existing S3-compatible adapter config", () => {
    const parsed = parseSnapshotArtifactStoreConfig({
      env: {
        [SNAPSHOT_ARTIFACT_STORE_KIND_ENV]: "supabase",
        [SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF_ENV]: "leqlomnszaboypinjroc",
        [SNAPSHOT_ARTIFACT_SUPABASE_BUCKET_ENV]: "snapshot-artifacts",
        [SNAPSHOT_ARTIFACT_SUPABASE_REGION_ENV]: "eu-central-1",
        [SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID_ENV]: "server-only-access-key",
        [SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY_ENV]: "server-only-secret"
      },
      requireHostedStore: true
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.config.kind, "s3");
    assert.equal(parsed.config.provider, "supabase_storage");
    assert.equal(parsed.config.bucket, "snapshot-artifacts");
    assert.equal(parsed.config.region, "eu-central-1");
    assert.equal(
      parsed.config.endpoint,
      "https://leqlomnszaboypinjroc.storage.supabase.co/storage/v1/s3"
    );
    assert.deepEqual(parsed.config.credentials, {
      accessKeyId: "server-only-access-key",
      secretAccessKey: "server-only-secret"
    });
  });

  it("fails closed for incomplete or malformed Supabase Storage configuration without echoing secrets", () => {
    const parsed = parseSnapshotArtifactStoreConfig({
      env: {
        [SNAPSHOT_ARTIFACT_STORE_KIND_ENV]: "supabase",
        [SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF_ENV]: "not-a-project-ref",
        [SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID_ENV]: "server-only-access-key",
        [SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY_ENV]: "secret-must-not-leak"
      },
      requireHostedStore: true
    });
    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    const codes = parsed.blocks.map((block) => block.code);
    assert.ok(codes.includes("artifact_supabase_project_ref_invalid"));
    assert.ok(codes.includes("artifact_supabase_bucket_missing"));
    assert.ok(codes.includes("artifact_supabase_region_missing"));
    assert.doesNotMatch(JSON.stringify(parsed.blocks), /secret-must-not-leak/);
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
