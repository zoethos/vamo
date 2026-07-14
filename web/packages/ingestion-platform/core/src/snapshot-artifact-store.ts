/**
 * Immutable snapshot artifact store adapter contract (IP-18.8.10).
 */

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

import {
  readSnapshotArtifactField,
  SNAPSHOT_ARTIFACT_BUNDLE_FILES
} from "./snapshot-artifact-bundle.js";
import { writeImmutableArtifactContent } from "./snapshot-artifact-immutable-write.js";
import { assertArtifactKeySafe } from "./snapshot-artifact-key.js";
import {
  classifyArtifactReadError,
  isObjectNotFoundError,
  SnapshotArtifactStorageError
} from "./snapshot-artifact-storage-error.js";
import type { SnapshotIntakeArtifacts } from "./versioned-snapshot-intake.js";
import { sha256Hex } from "./versioned-snapshot-intake.js";

export { SNAPSHOT_ARTIFACT_BUNDLE_FILES } from "./snapshot-artifact-bundle.js";

export interface SnapshotArtifactStore {
  putReleaseBundle(input: {
    artifactKey: string;
    artifacts: SnapshotIntakeArtifacts;
  }): Promise<SnapshotArtifactStorePutResult>;
  readReleaseBundle(input: { artifactKey: string }): Promise<SnapshotIntakeArtifacts>;
  verifyReleaseBundle(input: {
    artifactKey: string;
    expectedBundleSha256: string;
  }): Promise<boolean>;
}

export interface SnapshotArtifactStorePutResult {
  artifactKey: string;
  artifactUri: string;
  bundleSha256: string;
}

export function deriveSnapshotArtifactKey(input: {
  sourceKey: string;
  releaseId: string;
  outputSha256: string;
}): string {
  return `${input.sourceKey}/${input.releaseId}/${input.outputSha256}`;
}

export function computeSnapshotArtifactBundleSha256(artifacts: SnapshotIntakeArtifacts): string {
  const digest = createHash("sha256");
  for (const fileName of SNAPSHOT_ARTIFACT_BUNDLE_FILES) {
    const content = readSnapshotArtifactField(artifacts, fileName);
    digest.update(fileName);
    digest.update("\0");
    digest.update(content);
    digest.update("\0");
  }
  return digest.digest("hex");
}

export function createLocalSnapshotArtifactStore(baseDir: string): SnapshotArtifactStore {
  const rootDir = resolve(baseDir);
  const store: SnapshotArtifactStore = {
    async putReleaseBundle(input) {
      if (!assertArtifactKeySafe(input.artifactKey)) {
        throw new SnapshotArtifactStorageError("artifact_key_unsafe", "Artifact key is unsafe.");
      }

      const artifactDir = join(rootDir, ...input.artifactKey.split("/"));
      const expectedBundleSha256 = computeSnapshotArtifactBundleSha256(input.artifacts);

      for (const fileName of SNAPSHOT_ARTIFACT_BUNDLE_FILES) {
        const filePath = join(artifactDir, fileName);
        const expectedContent = readSnapshotArtifactField(input.artifacts, fileName);
        await writeImmutableArtifactContent({
          expectedContent,
          readExisting: async () => {
            if (!existsSync(filePath)) {
              return null;
            }
            try {
              return readFileSync(filePath, "utf8");
            } catch (error) {
              throw classifyArtifactReadError(error);
            }
          },
          writeIfAbsent: async (content) => {
            mkdirSync(artifactDir, { recursive: true });
            try {
              writeFileSync(filePath, content, { encoding: "utf8", flag: "wx" });
            } catch (error) {
              if (isObjectNotFoundError(error)) {
                throw error;
              }
              throw classifyArtifactReadError(error);
            }
          }
        });
      }

      const loaded = await store.readReleaseBundle({ artifactKey: input.artifactKey });
      const bundleSha256 = computeSnapshotArtifactBundleSha256(loaded);
      if (bundleSha256 !== expectedBundleSha256) {
        throw new SnapshotArtifactStorageError(
          "artifact_bundle_conflict",
          "Verified local bundle checksum does not match expected content."
        );
      }

      return {
        artifactKey: input.artifactKey,
        artifactUri: `file://${artifactDir}`,
        bundleSha256
      };
    },
    async readReleaseBundle(input) {
      if (!assertArtifactKeySafe(input.artifactKey)) {
        throw new SnapshotArtifactStorageError("artifact_key_unsafe", "Artifact key is unsafe.");
      }

      const artifactDir = join(rootDir, ...input.artifactKey.split("/"));
      const artifacts: Partial<SnapshotIntakeArtifacts> = {};
      let foundCount = 0;

      for (const fileName of SNAPSHOT_ARTIFACT_BUNDLE_FILES) {
        const filePath = join(artifactDir, fileName);
        if (!existsSync(filePath)) {
          continue;
        }
        try {
          artifacts[artifactFieldName(fileName)] = readFileSync(filePath, "utf8");
          foundCount += 1;
        } catch (error) {
          throw classifyArtifactReadError(error);
        }
      }

      if (foundCount === 0) {
        throw new SnapshotArtifactStorageError(
          "artifact_bundle_missing",
          "Snapshot artifact bundle was not found."
        );
      }
      if (foundCount !== SNAPSHOT_ARTIFACT_BUNDLE_FILES.length) {
        throw new SnapshotArtifactStorageError(
          "artifact_bundle_incomplete",
          "Snapshot artifact bundle is incomplete."
        );
      }

      return artifacts as SnapshotIntakeArtifacts;
    },
    async verifyReleaseBundle(input) {
      const artifacts = await store.readReleaseBundle({ artifactKey: input.artifactKey });
      return computeSnapshotArtifactBundleSha256(artifacts) === input.expectedBundleSha256;
    }
  };
  return store;
}

export function verifySnapshotArtifactBundleContents(artifacts: SnapshotIntakeArtifacts): boolean {
  if (!artifacts.sourceJsonl.trim() || !artifacts.releaseJson.trim() || !artifacts.coverageReportJson.trim()) {
    return false;
  }
  const release = JSON.parse(artifacts.releaseJson) as { outputSha256?: string };
  return sha256Hex(artifacts.sourceJsonl) === release.outputSha256;
}

function artifactFieldName(
  fileName: (typeof SNAPSHOT_ARTIFACT_BUNDLE_FILES)[number]
): keyof SnapshotIntakeArtifacts {
  if (fileName === "source.jsonl") {
    return "sourceJsonl";
  }
  if (fileName === "release.json") {
    return "releaseJson";
  }
  return "coverageReportJson";
}
