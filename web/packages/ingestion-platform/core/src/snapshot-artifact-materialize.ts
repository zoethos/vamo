/**
 * Materialize a verified snapshot artifact bundle to a trusted temp directory.
 *
 * Server/job only — used when pipeline execution still expects a local root.
 */

import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { assertArtifactKeySafe } from "./snapshot-artifact-key.js";
import {
  SNAPSHOT_ARTIFACT_BUNDLE_FILES,
  type SnapshotArtifactStore
} from "./snapshot-artifact-store.js";

export async function materializeArtifactBundleToTempDir(input: {
  store: SnapshotArtifactStore;
  artifactKey: string;
}): Promise<string> {
  if (!assertArtifactKeySafe(input.artifactKey)) {
    throw new Error("artifact_key_unsafe");
  }

  const artifacts = await input.store.readReleaseBundle({ artifactKey: input.artifactKey });
  const tempRoot = mkdtempSync(join(tmpdir(), "confluendo-snapshot-artifact-"));
  const artifactDir = join(tempRoot, ...input.artifactKey.split("/"));
  mkdirSync(artifactDir, { recursive: true });
  for (const fileName of SNAPSHOT_ARTIFACT_BUNDLE_FILES) {
    const field =
      fileName === "source.jsonl"
        ? "sourceJsonl"
        : fileName === "release.json"
          ? "releaseJson"
          : "coverageReportJson";
    writeFileSync(join(artifactDir, fileName), artifacts[field], "utf8");
  }
  return artifactDir;
}
