import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  LEGACY_LOCAL_ARTIFACT_STORE_DIR_ENV,
  parseSnapshotArtifactStoreConfig,
  SNAPSHOT_ARTIFACT_STORE_KIND_ENV
} from "../../../core/src/snapshot-artifact-store-config.js";

describe("artifact adapter config re-export", () => {
  it("re-exports the core snapshot artifact store config parser", () => {
    const parsed = parseSnapshotArtifactStoreConfig({
      env: {
        [SNAPSHOT_ARTIFACT_STORE_KIND_ENV]: "local",
        [LEGACY_LOCAL_ARTIFACT_STORE_DIR_ENV]: "/tmp/local-artifacts"
      }
    });
    assert.equal(parsed.ok, true);
  });
});
