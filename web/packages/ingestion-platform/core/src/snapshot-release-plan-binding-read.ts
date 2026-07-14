/**
 * Active snapshot release plan binding read model (IP-18.8.11).
 *
 * Returns browser-safe metadata only — never artifact URIs or filesystem paths.
 */

import { Client, type QueryResult } from "pg";

export interface ActiveSnapshotReleasePlanBindingSummary {
  releaseId: string;
  sourceKey: string;
  status: "activated";
  /** Trusted-server integrity evidence. Never passed through to browser summaries. */
  artifactBundleSha256: string;
  validRowCount?: number;
  coverageSummary?: string;
}

export interface LoadActiveSnapshotReleasePlanBindingInput {
  connectionString?: string;
  client?: SnapshotReleaseBindingReadPgClientLike;
  projectKey: string;
  planKey: string;
}

export interface SnapshotReleaseBindingReadPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

interface BindingRow extends Record<string, unknown> {
  releaseId: string;
  sourceKey: string;
  artifactBundleSha256: string;
  coverage: Record<string, unknown>;
}

export async function loadActiveSnapshotReleasePlanBinding(
  input: LoadActiveSnapshotReleasePlanBindingInput
): Promise<ActiveSnapshotReleasePlanBindingSummary | null> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  try {
    const response = await client.query<BindingRow>(
      `
        select
          r.release_id as "releaseId",
          r.source_key as "sourceKey",
          b.artifact_bundle_sha256 as "artifactBundleSha256",
          b.coverage
        from ingestion_platform.ingestion_snapshot_release_plan_bindings b
        join ingestion_platform.ingestion_batch_plans bp on bp.id = b.batch_plan_id
        join ingestion_platform.ingestion_projects p on p.id = bp.project_id
        join ingestion_platform.ingestion_snapshot_releases r on r.id = b.release_id
        where p.project_key = $1
          and bp.plan_key = $2
          and b.status = 'active'
        limit 1
      `,
      [input.projectKey, input.planKey]
    );
    const row = response.rows[0];
    if (!row) {
      return null;
    }
    const validRowCount =
      typeof row.coverage.validRowCount === "number" ? row.coverage.validRowCount : undefined;
    const byCountry =
      row.coverage.byCountry && typeof row.coverage.byCountry === "object"
        ? Object.keys(row.coverage.byCountry as Record<string, unknown>).length
        : undefined;
    const coverageSummary =
      validRowCount !== undefined
        ? `${validRowCount} valid source row(s)${byCountry ? ` · ${byCountry} countries` : ""}`
        : undefined;

    return {
      releaseId: row.releaseId,
      sourceKey: row.sourceKey,
      status: "activated",
      artifactBundleSha256: row.artifactBundleSha256,
      validRowCount,
      coverageSummary
    };
  } catch (error) {
    if (isUndefinedTable(error)) {
      return null;
    }
    throw error;
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

export function toRegisteredSnapshotReleaseSummary(
  binding: ActiveSnapshotReleasePlanBindingSummary
): {
  releaseId: string;
  sourceKey: string;
  status: "activated";
  coverageSummary?: string;
  validRowCount?: number;
} {
  return {
    releaseId: binding.releaseId,
    sourceKey: binding.sourceKey,
    status: binding.status,
    coverageSummary: binding.coverageSummary,
    validRowCount: binding.validRowCount
  };
}

async function openClient(
  client?: SnapshotReleaseBindingReadPgClientLike,
  connectionString?: string
): Promise<{ client: SnapshotReleaseBindingReadPgClientLike; ownedClient?: Client }> {
  if (client) {
    return { client };
  }
  if (!connectionString?.trim()) {
    throw new Error("Control database connection is required to read snapshot release bindings.");
  }
  const ownedClient = new Client({ connectionString });
  await ownedClient.connect();
  return { client: ownedClient, ownedClient };
}

function isUndefinedTable(error: unknown): boolean {
  return error instanceof Error && /relation .* does not exist/i.test(error.message);
}
