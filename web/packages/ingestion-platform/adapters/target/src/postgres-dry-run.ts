import { Client, type QueryResult } from "pg";

import { buildShipmentDiff } from "../../../core/src/diff.js";
import type { StagedCandidate } from "../../../core/src/pipeline-runner.js";
import type {
  ShipmentCandidateRow,
  ShipmentPlan,
  ShipmentPlanIncompatibility
} from "../../../core/src/shipment-plan.js";
import type { TargetProjectSpec, TargetTableSpec } from "../../../spec/src/types.js";

export interface PostgresDryRunInput {
  target: TargetProjectSpec;
  candidates: StagedCandidate[];
  connectionString?: string;
  client?: PgClientLike;
}

export interface PgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

interface QualifiedTableName {
  schema: string;
  table: string;
  displayName: string;
}

interface TableColumnRow extends Record<string, unknown> {
  column_name: string;
}

export async function planPostgresDryRun(input: PostgresDryRunInput): Promise<ShipmentPlan> {
  if (!input.client && !input.connectionString) {
    throw new Error("Postgres dry-run requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Postgres dry-run client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    return await buildPlan(client, input.target, input.candidates);
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

async function buildPlan(
  client: PgClientLike,
  target: TargetProjectSpec,
  candidates: StagedCandidate[]
): Promise<ShipmentPlan> {
  const items: ShipmentPlan["items"] = [];
  const incompatibilities: ShipmentPlanIncompatibility[] = [];

  for (const tableSpec of target.shipment.tables) {
    const qualified = parseTableName(tableSpec.table);
    const tableExists = await hasTable(client, qualified);
    if (!tableExists) {
      incompatibilities.push({
        code: "missing_table",
        table: qualified.displayName,
        message: `Target table "${qualified.displayName}" does not exist.`
      });
      continue;
    }

    const columns = await listColumns(client, qualified);
    const tableIncompatibilitiesBeforeChecks = incompatibilities.length;
    const tableRows = extractCandidateRows(candidates, tableSpec, qualified, incompatibilities);
    validateColumns(tableRows, tableSpec, qualified, columns, incompatibilities);

    if (incompatibilities.length > tableIncompatibilitiesBeforeChecks) {
      continue;
    }

    const existingRows = await loadExistingRows(client, qualified, tableSpec.upsertKeys, tableRows);
    items.push(
      ...buildShipmentDiff({
        targetTable: qualified.displayName,
        upsertKeys: tableSpec.upsertKeys,
        candidateRows: tableRows,
        existingRows
      })
    );
  }

  return {
    mode: "dry_run",
    targetId: target.id,
    targetProject: target.name,
    compatible: incompatibilities.length === 0,
    items,
    incompatibilities
  };
}

function extractCandidateRows(
  candidates: StagedCandidate[],
  tableSpec: TargetTableSpec,
  qualified: QualifiedTableName,
  incompatibilities: ShipmentPlanIncompatibility[]
): ShipmentCandidateRow[] {
  return candidates.flatMap((candidate) => {
    const payload = readTablePayload(candidate.payload, qualified);

    if (payload === undefined) {
      return [];
    }

    if (!isRecord(payload)) {
      incompatibilities.push({
        code: "invalid_table_payload",
        table: qualified.displayName,
        recordKey: candidate.recordKey,
        message: `Candidate payload for "${qualified.displayName}" must be an object.`
      });
      return [];
    }

    for (const key of tableSpec.upsertKeys) {
      if (payload[key] === undefined || payload[key] === null || payload[key] === "") {
        incompatibilities.push({
          code: "missing_upsert_key",
          table: qualified.displayName,
          column: key,
          recordKey: candidate.recordKey,
          message: `Candidate "${candidate.recordKey}" is missing upsert key "${key}" for "${qualified.displayName}".`
        });
      }
    }

    return [
      {
        recordKey: candidate.recordKey,
        payload
      }
    ];
  });
}

function validateColumns(
  rows: ShipmentCandidateRow[],
  tableSpec: TargetTableSpec,
  qualified: QualifiedTableName,
  columns: Set<string>,
  incompatibilities: ShipmentPlanIncompatibility[]
): void {
  for (const upsertKey of tableSpec.upsertKeys) {
    if (!columns.has(upsertKey)) {
      incompatibilities.push({
        code: "missing_column",
        table: qualified.displayName,
        column: upsertKey,
        message: `Target table "${qualified.displayName}" is missing upsert key column "${upsertKey}".`
      });
    }
  }

  for (const row of rows) {
    for (const column of Object.keys(row.payload)) {
      if (!columns.has(column)) {
        incompatibilities.push({
          code: "missing_column",
          table: qualified.displayName,
          column,
          recordKey: row.recordKey,
          message: `Target table "${qualified.displayName}" is missing payload column "${column}".`
        });
      }
    }
  }
}

async function loadExistingRows(
  client: PgClientLike,
  qualified: QualifiedTableName,
  upsertKeys: string[],
  rows: ShipmentCandidateRow[]
): Promise<Array<Record<string, unknown>>> {
  if (rows.length === 0) {
    return [];
  }

  const selectedColumns = [...new Set(rows.flatMap((row) => Object.keys(row.payload)).concat(upsertKeys))];
  const values: unknown[] = [];
  const conditions = rows.map((row) => {
    const keyConditions = upsertKeys.map((key) => {
      values.push(row.payload[key]);
      return `${quoteIdentifier(key)} = $${values.length}`;
    });
    return `(${keyConditions.join(" and ")})`;
  });

  const result = await client.query(
    `
      select ${selectedColumns.map(quoteIdentifier).join(", ")}
      from ${quoteIdentifier(qualified.schema)}.${quoteIdentifier(qualified.table)}
      where ${conditions.join(" or ")}
    `,
    values
  );

  return result.rows;
}

async function hasTable(client: PgClientLike, qualified: QualifiedTableName): Promise<boolean> {
  const result = await client.query<{ exists: boolean }>(
    `
      select exists (
        select 1
        from information_schema.tables
        where table_schema = $1
          and table_name = $2
      ) as "exists"
    `,
    [qualified.schema, qualified.table]
  );

  return result.rows[0]?.exists === true;
}

async function listColumns(
  client: PgClientLike,
  qualified: QualifiedTableName
): Promise<Set<string>> {
  const result = await client.query<TableColumnRow>(
    `
      select column_name
      from information_schema.columns
      where table_schema = $1
        and table_name = $2
    `,
    [qualified.schema, qualified.table]
  );

  return new Set(result.rows.map((row) => row.column_name));
}

function readTablePayload(
  payload: Record<string, unknown>,
  qualified: QualifiedTableName
): unknown {
  return payload[qualified.displayName] ?? payload[qualified.table];
}

function parseTableName(table: string): QualifiedTableName {
  const parts = table.split(".");
  const schema = parts.length === 2 ? parts[0] : "public";
  const tableName = parts.length === 2 ? parts[1] : parts[0];

  if (!schema || !tableName) {
    throw new Error(`Invalid target table name: ${table}`);
  }

  return {
    schema,
    table: tableName,
    displayName: parts.length === 2 ? `${schema}.${tableName}` : tableName
  };
}

function quoteIdentifier(identifier: string): string {
  return `"${identifier.replaceAll('"', '""')}"`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
