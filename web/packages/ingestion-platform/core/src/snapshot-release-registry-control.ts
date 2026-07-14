/**
 * Control-plane snapshot release registry adapter (IP-18.8.10).
 */

import { Client, type QueryResult } from "pg";

import type { SourceAcquisitionReleaseRecord } from "./source-acquisition-contract.js";

export interface SnapshotReleaseRegistryPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface RegisterSnapshotReleaseInput {
  connectionString?: string;
  client?: SnapshotReleaseRegistryPgClientLike;
  projectKey: string;
  release: SourceAcquisitionReleaseRecord;
  actor: {
    type: string;
    id: string;
  };
  auditReason: string;
  registrationMetadata?: Record<string, string>;
}

export interface RegisterSnapshotReleaseResult {
  ok: true;
  releaseId: string;
  auditId: string;
  status: "activation_ready";
}

interface RegisterRow extends Record<string, unknown> {
  result: {
    ok?: unknown;
    releaseId?: unknown;
    auditId?: unknown;
    status?: unknown;
  };
}

export async function registerSnapshotRelease(
  input: RegisterSnapshotReleaseInput
): Promise<RegisterSnapshotReleaseResult> {
  const client =
    input.client ??
    (input.connectionString ? new Client({ connectionString: input.connectionString }) : null);
  if (!client) {
    throw new Error("Control database connection is required to register snapshot releases.");
  }

  const ownsClient = Boolean(input.connectionString && !input.client);
  if (ownsClient) {
    await (client as Client).connect();
  }

  try {
    const response = await client.query<RegisterRow>(
      `
        select ingestion_platform.register_snapshot_release(
          $1,
          $2,
          $3,
          $4,
          $5,
          $6,
          $7,
          $8,
          $9,
          $10,
          $11,
          $12,
          $13,
          $14,
          $15,
          $16::jsonb,
          $17,
          $18,
          $19,
          $20::jsonb
        ) as result
      `,
      [
        input.projectKey,
        input.release.releaseId,
        input.release.sourceKey,
        input.release.sourceProvider,
        input.release.acquiredAt,
        input.release.provenanceUrl,
        input.release.inputSha256,
        input.release.outputSha256,
        input.release.sourceAttribution,
        input.release.licenseIdentifier,
        input.release.retentionStatement,
        input.release.intendedConsumer,
        input.release.intendedTarget,
        input.release.artifactKey,
        input.release.artifactUri,
        JSON.stringify(input.release.coverage),
        input.actor.type,
        input.actor.id,
        input.auditReason,
        JSON.stringify(input.registrationMetadata ?? {})
      ]
    );

    const result = response.rows[0]?.result;
    if (!result?.ok) {
      throw new Error("register_snapshot_release returned an unexpected payload.");
    }

    return {
      ok: true,
      releaseId: String(result.releaseId),
      auditId: String(result.auditId),
      status: "activation_ready"
    };
  } finally {
    if (ownsClient) {
      await (client as Client).end();
    }
  }
}
