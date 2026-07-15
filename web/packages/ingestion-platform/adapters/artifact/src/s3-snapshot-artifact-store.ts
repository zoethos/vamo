/**
 * S3-compatible snapshot artifact store adapter (IP-18.8.12).
 *
 * Server/job only. Integrity is derived from bundle contents, never object ETags.
 */

import {
  readSnapshotArtifactField,
  SNAPSHOT_ARTIFACT_BUNDLE_FILES
} from "../../../core/src/snapshot-artifact-bundle.js";
import { writeImmutableArtifactContent } from "../../../core/src/snapshot-artifact-immutable-write.js";
import {
  assertArtifactKeySafe,
  objectKeyForArtifactBundleFile
} from "../../../core/src/snapshot-artifact-key.js";
import {
  computeSnapshotArtifactBundleSha256,
  type SnapshotArtifactStore,
  type SnapshotArtifactStorePutResult
} from "../../../core/src/snapshot-artifact-store.js";
import {
  classifyArtifactReadError,
  isObjectNotFoundError,
  SnapshotArtifactStorageError
} from "../../../core/src/snapshot-artifact-storage-error.js";
import type { SnapshotIntakeArtifacts } from "../../../core/src/versioned-snapshot-intake.js";
import type { SnapshotArtifactStoreS3Config } from "../../../core/src/snapshot-artifact-store-config.js";

export interface S3ObjectClientLike {
  headBucket(input: { bucket: string }): Promise<void>;
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
  const store: SnapshotArtifactStore = {
    async putReleaseBundle({ artifactKey, artifacts }) {
      if (!assertArtifactKeySafe(artifactKey)) {
        throw new SnapshotArtifactStorageError("artifact_key_unsafe", "Artifact key is unsafe.");
      }

      const expectedBundleSha256 = computeSnapshotArtifactBundleSha256(artifacts);

      for (const fileName of SNAPSHOT_ARTIFACT_BUNDLE_FILES) {
        const key = resolveObjectKey(config, artifactKey, fileName);
        const expectedContent = readSnapshotArtifactField(artifacts, fileName);
        await writeImmutableArtifactContent({
          expectedContent,
          readExisting: async () => readObjectBodyOrNull(client, config.bucket, key),
          writeIfAbsent: async (content) => {
            await client.putObject({
              bucket: config.bucket,
              key,
              body: content,
              ifNoneMatch: "*"
            });
          }
        });
      }

      const loaded = await store.readReleaseBundle({ artifactKey });
      const bundleSha256 = computeSnapshotArtifactBundleSha256(loaded);
      if (bundleSha256 !== expectedBundleSha256) {
        throw new SnapshotArtifactStorageError(
          "artifact_bundle_conflict",
          "Verified S3 bundle checksum does not match expected content."
        );
      }

      return {
        artifactKey,
        artifactUri: buildInternalArtifactUri(config, artifactKey),
        bundleSha256
      } satisfies SnapshotArtifactStorePutResult;
    },

    async readReleaseBundle({ artifactKey }) {
      if (!assertArtifactKeySafe(artifactKey)) {
        throw new SnapshotArtifactStorageError("artifact_key_unsafe", "Artifact key is unsafe.");
      }

      const artifacts: Partial<SnapshotIntakeArtifacts> = {};
      let foundCount = 0;

      for (const fileName of SNAPSHOT_ARTIFACT_BUNDLE_FILES) {
        const key = resolveObjectKey(config, artifactKey, fileName);
        const body = await readObjectBodyOrNull(client, config.bucket, key);
        if (body === null) {
          continue;
        }
        artifacts[artifactFieldName(fileName)] = body;
        foundCount += 1;
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

    async verifyReleaseBundle({ artifactKey, expectedBundleSha256 }) {
      const artifacts = await store.readReleaseBundle({ artifactKey });
      return computeSnapshotArtifactBundleSha256(artifacts) === expectedBundleSha256;
    }
  };

  return store;
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
  fileName: (typeof SNAPSHOT_ARTIFACT_BUNDLE_FILES)[number]
): string {
  const objectKey = objectKeyForArtifactBundleFile(artifactKey, fileName);
  return config.prefix ? `${config.prefix}/${objectKey}` : objectKey;
}

async function readObjectBodyOrNull(
  client: S3ObjectClientLike,
  bucket: string,
  key: string
): Promise<string | null> {
  try {
    const response = await client.getObject({ bucket, key });
    return response.body;
  } catch (error) {
    if (isObjectNotFoundError(error)) {
      return null;
    }
    throw classifyArtifactReadError(error);
  }
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
