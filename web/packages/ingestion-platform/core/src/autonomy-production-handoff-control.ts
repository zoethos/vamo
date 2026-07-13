/**
 * Control-plane adapter for production package autonomy handoff.
 *
 * The database function owns the policy mutation, transition evidence, audit
 * row, and event row. Routes should call this adapter instead of updating
 * ingestion_autonomy_policies directly.
 */

import { Client, type QueryResult } from "pg";

import type { CommandActorType } from "./commands.js";

export interface AutonomyProductionHandoffControlPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface SetAutonomyProductionHandoffInput {
  connectionString?: string;
  client?: AutonomyProductionHandoffControlPgClientLike;
  projectKey: string;
  policyKey: string;
  expectedEnabled: boolean;
  requestedEnabled: boolean;
  actor: {
    type: CommandActorType;
    id: string;
  };
  auditReason: string;
}

export interface SetAutonomyProductionHandoffResult {
  ok: true;
  policyId: string;
  fromEnabled: boolean;
  toEnabled: boolean;
  policyVersion: number;
  auditId: string;
  productionInboxHandoffPolicy: Record<string, unknown>;
  allowedTransitions: string[];
}

interface HandoffRow extends Record<string, unknown> {
  result: {
    ok?: unknown;
    policyId?: unknown;
    fromEnabled?: unknown;
    toEnabled?: unknown;
    policyVersion?: unknown;
    auditId?: unknown;
    productionInboxHandoffPolicy?: unknown;
    allowedTransitions?: unknown;
  };
}

export async function setAutonomyProductionHandoff(
  input: SetAutonomyProductionHandoffInput
): Promise<SetAutonomyProductionHandoffResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);

  try {
    const result = await client.query<HandoffRow>(
      `
        select ingestion_platform.set_autonomy_production_handoff(
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
        input.policyKey,
        input.expectedEnabled,
        input.requestedEnabled,
        input.actor.type,
        input.actor.id,
        input.auditReason
      ]
    );

    const row = result.rows[0]?.result;
    if (
      row?.ok !== true ||
      typeof row.policyId !== "string" ||
      typeof row.fromEnabled !== "boolean" ||
      typeof row.toEnabled !== "boolean" ||
      typeof row.policyVersion !== "number" ||
      typeof row.auditId !== "string" ||
      !isRecord(row.productionInboxHandoffPolicy) ||
      !Array.isArray(row.allowedTransitions)
    ) {
      throw new Error("Production handoff control returned an invalid response.");
    }

    return {
      ok: true,
      policyId: row.policyId,
      fromEnabled: row.fromEnabled,
      toEnabled: row.toEnabled,
      policyVersion: row.policyVersion,
      auditId: row.auditId,
      productionInboxHandoffPolicy: row.productionInboxHandoffPolicy,
      allowedTransitions: row.allowedTransitions.filter((value): value is string => typeof value === "string")
    };
  } catch (error) {
    throw normalizeProductionHandoffControlError(error);
  } finally {
    await closeClient(ownedClient);
  }
}

async function openClient(
  client?: AutonomyProductionHandoffControlPgClientLike,
  connectionString?: string
): Promise<{ client: AutonomyProductionHandoffControlPgClientLike; ownedClient?: Client }> {
  if (!client && !connectionString) {
    throw new Error("Production handoff control requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Production handoff control client could not be initialized.");
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

function normalizeProductionHandoffControlError(error: unknown): Error {
  if (error instanceof Error) {
    return error;
  }
  return new Error(String(error));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
