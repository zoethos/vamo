/**
 * Materialize a verified snapshot artifact bundle to a trusted temp directory.
 *
 * Server/job only — used when pipeline execution still expects a local root.
 */

import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  readSnapshotArtifactField,
  SNAPSHOT_ARTIFACT_BUNDLE_FILES
} from "./snapshot-artifact-bundle.js";
import { assertArtifactKeySafe } from "./snapshot-artifact-key.js";
import type { SnapshotArtifactStore } from "./snapshot-artifact-store.js";
import { SnapshotArtifactStorageError } from "./snapshot-artifact-storage-error.js";

export interface MaterializedSnapshotArtifactBundle {
  artifactDir: string;
  dispose: () => Promise<void>;
}

export async function materializeArtifactBundleToScopedDir(input: {
  store: SnapshotArtifactStore;
  artifactKey: string;
}): Promise<MaterializedSnapshotArtifactBundle> {
  if (!assertArtifactKeySafe(input.artifactKey)) {
    throw new SnapshotArtifactStorageError("artifact_key_unsafe", "Artifact key is unsafe.");
  }

  const artifacts = await input.store.readReleaseBundle({ artifactKey: input.artifactKey });
  const tempRoot = mkdtempSync(join(tmpdir(), "confluendo-snapshot-artifact-"));
  const artifactDir = join(tempRoot, ...input.artifactKey.split("/"));
  let disposed = false;

  const dispose = async () => {
    if (disposed) {
      return;
    }
    disposed = true;
    rmSync(tempRoot, { recursive: true, force: true });
  };

  try {
    mkdirSync(artifactDir, { recursive: true });
    for (const fileName of SNAPSHOT_ARTIFACT_BUNDLE_FILES) {
      writeFileSync(
        join(artifactDir, fileName),
        readSnapshotArtifactField(artifacts, fileName),
        "utf8"
      );
    }
    return { artifactDir, dispose };
  } catch (error) {
    await dispose();
    throw error;
  }
}
