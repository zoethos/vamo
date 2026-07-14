/**
 * Control-plane snapshot release activation adapter (IP-18.8.11).
 */

import { Client, type QueryResult } from "pg";

import type { SourceAcquisitionReleaseRecord } from "./source-acquisition-contract.js";

export interface SnapshotReleaseActivationPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface LoadSnapshotReleaseForActivationInput {
  connectionString?: string;
  client?: SnapshotReleaseActivationPgClientLike;
  projectKey: string;
  releaseId: string;
}

export interface LoadBatchPlanSpecForActivationInput {
  connectionString?: string;
  client?: SnapshotReleaseActivationPgClientLike;
  projectKey: string;
  planKey: string;
}

export interface ActivateSnapshotReleaseInput {
  connectionString?: string;
  client?: SnapshotReleaseActivationPgClientLike;
  projectKey: string;
  planKey: string;
  releaseId: string;
  artifactBundleSha256: string;
  actor: { type: string; id: string };
  auditReason: string;
}

export interface ActivateSnapshotReleaseResult {
  ok: true;
  bindingId: string;
  releaseId: string;
  planKey: string;
  auditId: string;
  status: "activated";
}

interface ReleaseRow extends Record<string, unknown> {
  releaseId: string;
  sourceKey: string;
  sourceProvider: string;
  status: string;
  acquiredAt: string;
  provenanceUrl: string;
  inputSha256: string;
  outputSha256: string;
  sourceAttribution: string;
  licenseIdentifier: string;
  retentionStatement: string;
  intendedConsumer: string;
  intendedTarget: string;
  artifactKey: string;
  coverage: Record<string, unknown>;
}

interface ActivateRow extends Record<string, unknown> {
  result: {
    ok?: unknown;
    bindingId?: unknown;
    releaseId?: unknown;
    planKey?: unknown;
    auditId?: unknown;
    status?: unknown;
  };
}

interface PlanSpecRow extends Record<string, unknown> {
  spec: Record<string, unknown>;
}

export async function loadBatchPlanSpecForActivation(
  input: LoadBatchPlanSpecForActivationInput
): Promise<Record<string, unknown> | null> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  try {
    const response = await client.query<PlanSpecRow>(
      `
        select bp.spec as spec
        from ingestion_platform.ingestion_batch_plans bp
        join ingestion_platform.ingestion_projects p on p.id = bp.project_id
        where p.project_key = $1
          and bp.plan_key = $2
        limit 1
      `,
      [input.projectKey, input.planKey]
    );
    return response.rows[0]?.spec ?? null;
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

export async function loadSnapshotReleaseForActivation(
  input: LoadSnapshotReleaseForActivationInput
): Promise<SourceAcquisitionReleaseRecord | null> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  try {
    const response = await client.query<ReleaseRow>(
      `
        select
          r.release_id as "releaseId",
          r.source_key as "sourceKey",
          r.source_provider as "sourceProvider",
          r.status,
          r.acquired_at as "acquiredAt",
          r.provenance_url as "provenanceUrl",
          r.input_sha256 as "inputSha256",
          r.output_sha256 as "outputSha256",
          r.source_attribution as "sourceAttribution",
          r.license_identifier as "licenseIdentifier",
          r.retention_statement as "retentionStatement",
          r.intended_consumer as "intendedConsumer",
          r.intended_target as "intendedTarget",
          r.artifact_key as "artifactKey",
          r.coverage
        from ingestion_platform.ingestion_snapshot_releases r
        join ingestion_platform.ingestion_projects p on p.id = r.project_id
        where p.project_key = $1
          and r.release_id = $2
        limit 1
      `,
      [input.projectKey, input.releaseId]
    );
    const row = response.rows[0];
    if (!row) {
      return null;
    }
    return {
      kind: "ingestion.source_acquisition_release",
      releaseId: row.releaseId,
      sourceKey: row.sourceKey,
      sourceProvider: row.sourceProvider,
      acquiredAt: row.acquiredAt,
      provenanceUrl: row.provenanceUrl,
      inputSha256: row.inputSha256,
      outputSha256: row.outputSha256,
      sourceAttribution: row.sourceAttribution,
      licenseIdentifier: row.licenseIdentifier,
      retentionStatement: row.retentionStatement,
      intendedConsumer: row.intendedConsumer,
      intendedTarget: row.intendedTarget,
      artifactKey: row.artifactKey,
      artifactUri: "",
      status: row.status as SourceAcquisitionReleaseRecord["status"],
      coverage: row.coverage as unknown as SourceAcquisitionReleaseRecord["coverage"],
      rowCounts: {
        valid: Number((row.coverage as { validRowCount?: number }).validRowCount ?? 0),
        invalid: 0,
        duplicate: 0,
        outOfScope: 0
      }
    };
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

export async function activateSnapshotRelease(
  input: ActivateSnapshotReleaseInput
): Promise<ActivateSnapshotReleaseResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  try {
    const response = await client.query<ActivateRow>(
      `
        select ingestion_platform.activate_snapshot_release(
          $1,
          $2,
          $3,
          $4,
          $5,
          $6,
          $7
        ) as result
      `,
      [
        input.projectKey,
        input.planKey,
        input.releaseId,
        input.artifactBundleSha256,
        input.actor.type,
        input.actor.id,
        input.auditReason
      ]
    );
    const result = response.rows[0]?.result;
    if (!result?.ok) {
      throw new Error("activate_snapshot_release returned an unexpected payload.");
    }
    return {
      ok: true,
      bindingId: String(result.bindingId),
      releaseId: String(result.releaseId),
      planKey: String(result.planKey),
      auditId: String(result.auditId),
      status: "activated"
    };
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

async function openClient(
  client?: SnapshotReleaseActivationPgClientLike,
  connectionString?: string
): Promise<{ client: SnapshotReleaseActivationPgClientLike; ownedClient?: Client }> {
  if (client) {
    return { client };
  }
  if (!connectionString?.trim()) {
    throw new Error("Control database connection is required for snapshot release activation.");
  }
  const ownedClient = new Client({ connectionString });
  await ownedClient.connect();
  return { client: ownedClient, ownedClient };
}
