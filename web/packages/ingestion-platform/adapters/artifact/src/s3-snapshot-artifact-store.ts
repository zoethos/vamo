/**
 * S3-compatible snapshot artifact store adapter (IP-18.8.12).
 *
 * Server/job only. Integrity is derived from bundle contents, never object ETags.
 */

import {
  computeSnapshotArtifactBundleSha256,
  SNAPSHOT_ARTIFACT_BUNDLE_FILES,
  type SnapshotArtifactStore,
  type SnapshotArtifactStorePutResult
} from "../../../core/src/snapshot-artifact-store.js";
import {
  assertArtifactKeySafe,
  objectKeyForArtifactBundleFile
} from "../../../core/src/snapshot-artifact-key.js";
import type { SnapshotIntakeArtifacts } from "../../../core/src/versioned-snapshot-intake.js";
import type { SnapshotArtifactStoreS3Config } from "./snapshot-artifact-store-config.js";

export interface S3ObjectClientLike {
  headObject(input: { bucket: string; key: string }): Promise<{ exists: boolean }>;
  getObject(input: { bucket: string; key: string }): Promise<{ body: string }>;
  putObject(input: {
    bucket: string;
    key: string;
    body: string;
    ifNoneMatch?: string;
  }): Promise<void>;
}

export interface CreateS3SnapshotArtifactStoreInput {
  config: SnapshotArtifactStoreS3Config;
  client: S3ObjectClientLike;
}

export function createS3SnapshotArtifactStore(
  input: CreateS3SnapshotArtifactStoreInput
): SnapshotArtifactStore {
  const { config, client } = input;

  return {
    async putReleaseBundle({ artifactKey, artifacts }) {
      if (!assertArtifactKeySafe(artifactKey)) {
        throw new Error("artifact_key_unsafe");
      }

      for (const fileName of SNAPSHOT_ARTIFACT_BUNDLE_FILES) {
        const key = resolveObjectKey(config, artifactKey, fileName);
        const existing = await client.headObject({ bucket: config.bucket, key });
        if (existing.exists) {
          throw new Error("artifact_bundle_already_exists");
        }
      }

      for (const fileName of SNAPSHOT_ARTIFACT_BUNDLE_FILES) {
        const key = resolveObjectKey(config, artifactKey, fileName);
        const body = readArtifactField(artifacts, fileName);
        await client.putObject({
          bucket: config.bucket,
          key,
          body,
          ifNoneMatch: "*"
        });
      }

      const bundleSha256 = computeSnapshotArtifactBundleSha256(artifacts);
      return {
        artifactKey,
        artifactUri: buildInternalArtifactUri(config, artifactKey),
        bundleSha256
      } satisfies SnapshotArtifactStorePutResult;
    },

    async readReleaseBundle({ artifactKey }) {
      if (!assertArtifactKeySafe(artifactKey)) {
        throw new Error("artifact_key_unsafe");
      }

      const sourceJsonl = await readObjectBody(client, config, artifactKey, "source.jsonl");
      const releaseJson = await readObjectBody(client, config, artifactKey, "release.json");
      const coverageReportJson = await readObjectBody(
        client,
        config,
        artifactKey,
        "coverage-report.json"
      );
      return { sourceJsonl, releaseJson, coverageReportJson };
    },

    async verifyReleaseBundle({ artifactKey, expectedBundleSha256 }) {
      const artifacts = await this.readReleaseBundle({ artifactKey });
      return computeSnapshotArtifactBundleSha256(artifacts) === expectedBundleSha256;
    }
  };
}

export function buildInternalArtifactUri(
  config: SnapshotArtifactStoreS3Config,
  artifactKey: string
): string {
  const prefix = config.prefix ? `${config.prefix}/` : "";
  return `s3://${config.bucket}/${prefix}${artifactKey}`;
}

function resolveObjectKey(
  config: SnapshotArtifactStoreS3Config,
  artifactKey: string,
  fileName: string
): string {
  const objectKey = objectKeyForArtifactBundleFile(artifactKey, fileName);
  return config.prefix ? `${config.prefix}/${objectKey}` : objectKey;
}

async function readObjectBody(
  client: S3ObjectClientLike,
  config: SnapshotArtifactStoreS3Config,
  artifactKey: string,
  fileName: string
): Promise<string> {
  const key = resolveObjectKey(config, artifactKey, fileName);
  try {
    const response = await client.getObject({ bucket: config.bucket, key });
    return response.body;
  } catch {
    throw new Error("artifact_bundle_missing");
  }
}

function readArtifactField(artifacts: SnapshotIntakeArtifacts, fileName: string): string {
  if (fileName === "source.jsonl") return artifacts.sourceJsonl;
  if (fileName === "release.json") return artifacts.releaseJson;
  return artifacts.coverageReportJson;
}
