/**
 * Snapshot artifact store factory for trusted server/job contexts (IP-18.8.12).
 */

import { createLocalSnapshotArtifactStore, type SnapshotArtifactStore } from "../../../core/src/snapshot-artifact-store.js";
import type { SnapshotArtifactStoreConfig } from "../../../core/src/snapshot-artifact-store-config.js";
import {
  classifyArtifactReadError,
  isObjectNotFoundError
} from "../../../core/src/snapshot-artifact-storage-error.js";
import {
  createS3SnapshotArtifactStore,
  type S3ObjectClientLike
} from "./s3-snapshot-artifact-store.js";

export interface CreateSnapshotArtifactStoreDeps {
  s3Client?: S3ObjectClientLike;
  createS3Client?: (config: Extract<SnapshotArtifactStoreConfig, { kind: "s3" }>) => Promise<S3ObjectClientLike>;
}

export async function createSnapshotArtifactStore(
  config: SnapshotArtifactStoreConfig,
  deps: CreateSnapshotArtifactStoreDeps = {}
): Promise<SnapshotArtifactStore> {
  if (config.kind === "local") {
    return createLocalSnapshotArtifactStore(config.baseDir);
  }

  const client = await resolveS3Client(config, deps);
  return createS3SnapshotArtifactStore({ config, client });
}

export interface VerifySnapshotArtifactStoreAccessResult {
  provider: "generic_s3" | "supabase_storage";
  bucket: string;
  region: string;
}

/**
 * Confirms trusted S3-compatible bucket access without reading or writing an artifact.
 * This is deliberately adapter-only: browser code never receives storage configuration.
 */
export async function verifySnapshotArtifactStoreAccess(
  config: SnapshotArtifactStoreConfig,
  deps: CreateSnapshotArtifactStoreDeps = {}
): Promise<VerifySnapshotArtifactStoreAccessResult> {
  if (config.kind !== "s3") {
    throw new Error("Artifact-store access verification requires a hosted S3-compatible store.");
  }
  const client = await resolveS3Client(config, deps);
  await client.headBucket({ bucket: config.bucket });
  return {
    provider: config.provider ?? "generic_s3",
    bucket: config.bucket,
    region: config.region
  };
}

async function resolveS3Client(
  config: Extract<SnapshotArtifactStoreConfig, { kind: "s3" }>,
  deps: CreateSnapshotArtifactStoreDeps
): Promise<S3ObjectClientLike> {
  return (
    deps.s3Client ??
    (deps.createS3Client ? await deps.createS3Client(config) : await createDefaultS3Client(config))
  );
}

async function createDefaultS3Client(
  config: Extract<SnapshotArtifactStoreConfig, { kind: "s3" }>
): Promise<S3ObjectClientLike> {
  const { S3Client, HeadBucketCommand, HeadObjectCommand, GetObjectCommand, PutObjectCommand } = await import(
    "@aws-sdk/client-s3"
  );
  const client = new S3Client({
    region: config.region,
    endpoint: config.endpoint,
    forcePathStyle: Boolean(config.endpoint),
    credentials: config.credentials
  });

  return {
    async headBucket(input) {
      try {
        await client.send(new HeadBucketCommand({ Bucket: input.bucket }));
      } catch (error) {
        throw classifyArtifactReadError(error);
      }
    },
    async headObject(input) {
      try {
        await client.send(new HeadObjectCommand({ Bucket: input.bucket, Key: input.key }));
        return { exists: true };
      } catch (error) {
        if (isObjectNotFoundError(error)) {
          return { exists: false };
        }
        throw classifyArtifactReadError(error);
      }
    },
    async getObject(input) {
      try {
        const response = await client.send(
          new GetObjectCommand({ Bucket: input.bucket, Key: input.key })
        );
        return { body: await streamToString(response.Body) };
      } catch (error) {
        throw classifyArtifactReadError(error);
      }
    },
    async putObject(input) {
      try {
        await client.send(
          new PutObjectCommand({
            Bucket: input.bucket,
            Key: input.key,
            Body: input.body,
            IfNoneMatch: input.ifNoneMatch
          })
        );
      } catch (error) {
        throw classifyArtifactReadError(error);
      }
    }
  };
}

async function streamToString(body: unknown): Promise<string> {
  if (!body) {
    return "";
  }
  if (typeof body === "string") {
    return body;
  }
  if (body instanceof Uint8Array) {
    return Buffer.from(body).toString("utf8");
  }
  if (typeof (body as { transformToString?: () => Promise<string> }).transformToString === "function") {
    return (body as { transformToString: () => Promise<string> }).transformToString();
  }
  const chunks: Buffer[] = [];
  for await (const chunk of body as AsyncIterable<Uint8Array | Buffer | string>) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}
