/**
 * Immutable snapshot artifact store adapter contract (IP-18.8.10).
 */

import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

import type { SnapshotIntakeArtifacts } from "./versioned-snapshot-intake.js";
import { sha256Hex } from "./versioned-snapshot-intake.js";

export const SNAPSHOT_ARTIFACT_BUNDLE_FILES = [
  "source.jsonl",
  "release.json",
  "coverage-report.json"
] as const;

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
    const content =
      fileName === "source.jsonl"
        ? artifacts.sourceJsonl
        : fileName === "release.json"
          ? artifacts.releaseJson
          : artifacts.coverageReportJson;
    digest.update(fileName);
    digest.update("\0");
    digest.update(content);
    digest.update("\0");
  }
  return digest.digest("hex");
}

export function createLocalSnapshotArtifactStore(baseDir: string): SnapshotArtifactStore {
  const rootDir = resolve(baseDir);
  return {
    async putReleaseBundle(input) {
      const artifactDir = join(rootDir, ...input.artifactKey.split("/"));
      mkdirSync(artifactDir, { recursive: true });
      writeFileSync(join(artifactDir, "source.jsonl"), input.artifacts.sourceJsonl, "utf8");
      writeFileSync(join(artifactDir, "release.json"), input.artifacts.releaseJson, "utf8");
      writeFileSync(
        join(artifactDir, "coverage-report.json"),
        input.artifacts.coverageReportJson,
        "utf8"
      );
      const bundleSha256 = computeSnapshotArtifactBundleSha256(input.artifacts);
      const artifactUri = `file://${join(artifactDir)}`;
      return {
        artifactKey: input.artifactKey,
        artifactUri,
        bundleSha256
      };
    },
    async readReleaseBundle(input) {
      const artifactDir = join(rootDir, ...input.artifactKey.split("/"));
      return {
        sourceJsonl: readFileSync(join(artifactDir, "source.jsonl"), "utf8"),
        releaseJson: readFileSync(join(artifactDir, "release.json"), "utf8"),
        coverageReportJson: readFileSync(join(artifactDir, "coverage-report.json"), "utf8")
      };
    },
    async verifyReleaseBundle(input) {
      const artifacts = await this.readReleaseBundle({ artifactKey: input.artifactKey });
      return computeSnapshotArtifactBundleSha256(artifacts) === input.expectedBundleSha256;
    }
  };
}

export function verifySnapshotArtifactBundleContents(artifacts: SnapshotIntakeArtifacts): boolean {
  if (!artifacts.sourceJsonl.trim() || !artifacts.releaseJson.trim() || !artifacts.coverageReportJson.trim()) {
    return false;
  }
  const release = JSON.parse(artifacts.releaseJson) as { outputSha256?: string };
  return sha256Hex(artifacts.sourceJsonl) === release.outputSha256;
}
