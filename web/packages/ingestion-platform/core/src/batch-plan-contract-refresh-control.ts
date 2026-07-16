/**
 * Control-plane adapter for audited, metadata-only batch-plan refreshes.
 * The SQL function is the single mutation authority; this module never
 * updates plans or queue rows directly.
 */

import { Client, type QueryResult } from "pg";

import type { CommandActorType } from "./commands.js";
import {
  parseFsqSourceTaxonomy,
  type FsqSourceTaxonomyMapping
} from "./fsq-source-taxonomy.js";

export interface BatchPlanContractRefreshPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface BatchPlanSourceTaxonomyState {
  projectKey: string;
  planKey: string;
  sourceKey: string;
  status: "active" | "archived";
  sourceTaxonomy: unknown;
}

export interface RefreshBatchPlanSourceTaxonomyResult {
  ok: true;
  changed: boolean;
  planId: string;
  planKey: string;
  sourceKey: string;
  auditId?: string;
  sourceTaxonomy: FsqSourceTaxonomyMapping;
}

interface PlanStateRow extends Record<string, unknown> {
  projectKey: string;
  planKey: string;
  sourceKey: string;
  status: "active" | "archived";
  sourceTaxonomy: unknown;
}

interface RefreshRow extends Record<string, unknown> {
  result: {
    ok?: unknown;
    changed?: unknown;
    planId?: unknown;
    planKey?: unknown;
    sourceKey?: unknown;
    auditId?: unknown;
    sourceTaxonomy?: unknown;
  };
}

export async function loadBatchPlanSourceTaxonomyState(input: {
  connectionString?: string;
  client?: BatchPlanContractRefreshPgClientLike;
  projectKey: string;
  planKey: string;
}): Promise<BatchPlanSourceTaxonomyState | null> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  try {
    const result = await client.query<PlanStateRow>(
      `
        select
          p.project_key as "projectKey",
          bp.plan_key as "planKey",
          bp.source_key as "sourceKey",
          bp.status,
          bp.spec->'sourceTaxonomy' as "sourceTaxonomy"
        from ingestion_platform.ingestion_batch_plans bp
        join ingestion_platform.ingestion_projects p on p.id = bp.project_id
        where p.project_key = $1 and bp.plan_key = $2
        limit 1
      `,
      [input.projectKey, input.planKey]
    );
    const row = result.rows[0];
    return row
      ? {
          projectKey: row.projectKey,
          planKey: row.planKey,
          sourceKey: row.sourceKey,
          status: row.status,
          sourceTaxonomy: row.sourceTaxonomy
        }
      : null;
  } finally {
    await closeClient(ownedClient);
  }
}

export async function refreshBatchPlanSourceTaxonomy(input: {
  connectionString?: string;
  client?: BatchPlanContractRefreshPgClientLike;
  projectKey: string;
  planKey: string;
  sourceKey: string;
  sourceTaxonomy: FsqSourceTaxonomyMapping;
  actor: { type: CommandActorType; id: string };
  auditReason: string;
}): Promise<RefreshBatchPlanSourceTaxonomyResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  try {
    const result = await client.query<RefreshRow>(
      `
        select ingestion_platform.refresh_batch_plan_source_taxonomy(
          $1, $2, $3, $4::jsonb, $5, $6, $7
        ) as result
      `,
      [
        input.projectKey,
        input.planKey,
        input.sourceKey,
        JSON.stringify(input.sourceTaxonomy),
        input.actor.type,
        input.actor.id,
        input.auditReason
      ]
    );
    const row = result.rows[0]?.result;
    if (
      row?.ok !== true ||
      typeof row.changed !== "boolean" ||
      typeof row.planId !== "string" ||
      typeof row.planKey !== "string" ||
      typeof row.sourceKey !== "string" ||
      (row.auditId !== undefined && typeof row.auditId !== "string") ||
      !isTaxonomy(row.sourceTaxonomy)
    ) {
      throw new Error("Plan contract refresh returned an invalid response.");
    }
    return {
      ok: true,
      changed: row.changed,
      planId: row.planId,
      planKey: row.planKey,
      sourceKey: row.sourceKey,
      auditId: row.auditId,
      sourceTaxonomy: row.sourceTaxonomy
    };
  } finally {
    await closeClient(ownedClient);
  }
}

async function openClient(
  client?: BatchPlanContractRefreshPgClientLike,
  connectionString?: string
): Promise<{ client: BatchPlanContractRefreshPgClientLike; ownedClient?: Client }> {
  if (!client && !connectionString) {
    throw new Error("Plan contract refresh requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Plan contract refresh client could not be initialized.");
  }
  if (ownedClient) {
    await ownedClient.connect();
  }
  return { client: resolved, ownedClient };
}

async function closeClient(client?: Client): Promise<void> {
  if (client) {
    await client.end();
  }
}

function isTaxonomy(value: unknown): value is FsqSourceTaxonomyMapping {
  return parseFsqSourceTaxonomy(value).ok;
}
