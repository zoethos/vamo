import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  verifySnapshotArtifactStoreAccess,
  type CreateSnapshotArtifactStoreDeps
} from "../src/create-snapshot-artifact-store.js";

describe("snapshot artifact store access verification", () => {
  it("probes a Supabase Storage bucket without writing an artifact", async () => {
    const calls: string[] = [];
    const deps: CreateSnapshotArtifactStoreDeps = {
      s3Client: {
        async headBucket(input) {
          calls.push(`headBucket:${input.bucket}`);
        },
        async headObject() {
          calls.push("headObject");
          return { exists: false };
        },
        async getObject() {
          calls.push("getObject");
          return { body: "" };
        },
        async putObject() {
          calls.push("putObject");
        }
      }
    };

    const result = await verifySnapshotArtifactStoreAccess(
      {
        kind: "s3",
        provider: "supabase_storage",
        bucket: "snapshot-artifacts",
        region: "eu-central-1",
        endpoint: "https://leqlomnszaboypinjroc.storage.supabase.co/storage/v1/s3",
        credentials: { accessKeyId: "server-only-access-key", secretAccessKey: "server-only-secret" }
      },
      deps
    );

    assert.deepEqual(result, {
      provider: "supabase_storage",
      bucket: "snapshot-artifacts",
      region: "eu-central-1"
    });
    assert.deepEqual(calls, ["headBucket:snapshot-artifacts"]);
  });

  it("refuses a local directory because hosted access verification has no filesystem fallback", async () => {
    await assert.rejects(
      () => verifySnapshotArtifactStoreAccess({ kind: "local", baseDir: "/secure/artifacts" }),
      /requires a hosted S3-compatible store/
    );
  });
});
