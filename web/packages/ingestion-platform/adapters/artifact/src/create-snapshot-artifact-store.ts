/**
 * Snapshot artifact store factory for trusted server/job contexts (IP-18.8.12).
 */

import { createLocalSnapshotArtifactStore, type SnapshotArtifactStore } from "../../../core/src/snapshot-artifact-store.js";
import {
  createS3SnapshotArtifactStore,
  type S3ObjectClientLike
} from "./s3-snapshot-artifact-store.js";
import type { SnapshotArtifactStoreConfig } from "./snapshot-artifact-store-config.js";

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

  const client =
    deps.s3Client ??
    (deps.createS3Client ? await deps.createS3Client(config) : await createDefaultS3Client(config));
  return createS3SnapshotArtifactStore({ config, client });
}

async function createDefaultS3Client(
  config: Extract<SnapshotArtifactStoreConfig, { kind: "s3" }>
): Promise<S3ObjectClientLike> {
  const { S3Client, HeadObjectCommand, GetObjectCommand, PutObjectCommand } = await import(
    "@aws-sdk/client-s3"
  );
  const client = new S3Client({
    region: config.region,
    endpoint: config.endpoint,
    forcePathStyle: Boolean(config.endpoint)
  });

  return {
    async headObject(input) {
      try {
        await client.send(new HeadObjectCommand({ Bucket: input.bucket, Key: input.key }));
        return { exists: true };
      } catch (error) {
        if (isNotFound(error)) {
          return { exists: false };
        }
        throw error;
      }
    },
    async getObject(input) {
      const response = await client.send(
        new GetObjectCommand({ Bucket: input.bucket, Key: input.key })
      );
      return { body: await streamToString(response.Body) };
    },
    async putObject(input) {
      await client.send(
        new PutObjectCommand({
          Bucket: input.bucket,
          Key: input.key,
          Body: input.body,
          IfNoneMatch: input.ifNoneMatch
        })
      );
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

function isNotFound(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    ("name" in error
      ? error.name === "NotFound" || error.name === "NoSuchKey"
      : false)
  );
}
