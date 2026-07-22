import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  classifyArtifactReadError,
  isObjectNotFoundError,
  SnapshotArtifactStorageError
} from "../src/snapshot-artifact-storage-error.js";

describe("snapshot artifact storage error classification", () => {
  it("classifies S3 authorization status responses without exposing the provider error", () => {
    const classified = classifyArtifactReadError({
      name: "UnknownError",
      $metadata: { httpStatusCode: 403 }
    });

    assert.equal(classified.code, "artifact_storage_access_denied");
    assert.equal(classified.message, "Snapshot artifact storage access was denied.");
  });

  it("classifies Signature V4 failures as access denial", () => {
    const classified = classifyArtifactReadError({
      name: "SignatureDoesNotMatch",
      code: "SignatureDoesNotMatch",
      $metadata: { httpStatusCode: 400 }
    });

    assert.equal(classified.code, "artifact_storage_access_denied");
  });

  it("keeps a wrapped missing-object error detectable by immutable writes", () => {
    const wrapped = new SnapshotArtifactStorageError(
      "artifact_bundle_missing",
      "Snapshot artifact bundle file was not found."
    );

    assert.equal(isObjectNotFoundError(wrapped), true);
  });
});
