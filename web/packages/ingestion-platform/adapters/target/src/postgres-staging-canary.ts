/**
 * Staging-canary shipment apply/rollback (IP-16) — the ONLY code path that
 * writes to a consumer (Vamo) target, and only ever staging.
 *
 * It reuses the proven dry-run planner (`planPostgresDryRun`) to compute and
 * validate the diff, then applies a bounded, idempotent upsert inside a single
 * transaction. It refuses to write unless:
 *
 * - the caller's `proveStaging` guard confirms the connection is staging,
 * - the re-planned diff is compatible,
 * - the diff has no `delete` and does not drift from the reviewed diff, and
 * - the write count is within the canary bound.
 *
 * Prior row state is captured for every `update` so the canary is reversible.
 * Any failure rolls the whole transaction back, leaving no partial canary.
 *
 * This module performs the target write; the promotion *decision* lives in the
 * pure `core/src/staging-canary-policy.ts`. Production has no path here.
 */

import { Client } from "pg";

import { STAGING_CANARY_MAX_ROWS } from "../../../core/src/staging-canary-policy.js";
import type { StagedCandidate } from "../../../core/src/pipeline-runner.js";
import type { ShipmentPlanIncompatibility } from "../../../core/src/shipment-plan.js";
import type { TargetProjectSpec, TargetTableSpec } from "../../../spec/src/types.js";
import { planPostgresDryRun, type PgClientLike } from "./postgres-dry-run.js";
import { parseTableName, quoteIdentifier, type QualifiedTableName } from "./table-name.js";

export type StagingCanaryBlockCode =
  | "staging_not_proven"
  | "incompatible_diff"
  | "delete_not_allowed"
  | "row_bound_exceeded"
  | "diff_drift";

export interface AppliedCanaryItem {
  targetTable: string;
  operation: "insert" | "update" | "no_op";
  recordKey: string;
  idempotencyKey: string;
  /** Upsert-key columns and values that identify the row. */
  keys: Record<string, unknown>;
  /** Columns written for this item. */
  columns: string[];
  /** Prior row state for `update` (for reversal); null for `insert`/`no_op`. */
  priorState: Record<string, unknown> | null;
}

export interface StagingCanaryCounts {
  insert: number;
  update: number;
  noOp: number;
  writeCount: number;
}

export interface ExpectedCanaryWrite {
  insert: number;
  update: number;
}

export interface ApplyPostgresStagingCanaryInput {
  target: TargetProjectSpec;
  candidates: StagedCandidate[];
  client?: PgClientLike;
  connectionString?: string;
  /**
   * MANDATORY staging guard. The canary refuses to write unless this resolves
   * to `true`. There is intentionally no default: a missing guard means no
   * write. For tests, pass `async () => true` against a disposable target.
   */
  proveStaging: (client: PgClientLike) => boolean | Promise<boolean>;
  /** Hard upper bound on written rows. Defaults to STAGING_CANARY_MAX_ROWS. */
  maxRows?: number;
  /** Reviewed diff counts; if provided, a drift fails the canary before writing. */
  expectedWrite?: ExpectedCanaryWrite;
}

export type ApplyPostgresStagingCanaryResult =
  | {
      ok: true;
      wroteToTarget: boolean;
      environment: "staging";
      counts: StagingCanaryCounts;
      items: AppliedCanaryItem[];
    }
  | {
      ok: false;
      code: StagingCanaryBlockCode;
      message: string;
      incompatibilities?: ShipmentPlanIncompatibility[];
    };

export interface RollbackPostgresStagingCanaryInput {
  /** Items returned by a prior successful `applyPostgresStagingCanary`. */
  items: AppliedCanaryItem[];
  client?: PgClientLike;
  connectionString?: string;
  proveStaging: (client: PgClientLike) => boolean | Promise<boolean>;
}

export interface RollbackPostgresStagingCanaryResult {
  ok: boolean;
  reverted: { deletedInserts: number; restoredUpdates: number };
}

export async function applyPostgresStagingCanary(
  input: ApplyPostgresStagingCanaryInput
): Promise<ApplyPostgresStagingCanaryResult> {
  const maxRows = input.maxRows ?? STAGING_CANARY_MAX_ROWS;
  return withClient(input, async (client) => {
    await client.query("begin");
    await client.query("set local statement_timeout = '15s'");
    try {
      if (!(await input.proveStaging(client))) {
        await client.query("rollback");
        return {
          ok: false,
          code: "staging_not_proven",
          message: "Refusing to write: the target connection was not proven to be staging."
        };
      }

      const plan = await planPostgresDryRun({
        client,
        target: input.target,
        candidates: input.candidates
      });

      if (!plan.compatible) {
        await client.query("rollback");
        return {
          ok: false,
          code: "incompatible_diff",
          message: `Refusing to write: shipment diff is incompatible (${plan.incompatibilities.length}).`,
          incompatibilities: plan.incompatibilities
        };
      }

      const deleteCount = plan.items.filter((item) => item.operation === "delete").length;
      if (deleteCount > 0) {
        await client.query("rollback");
        return {
          ok: false,
          code: "delete_not_allowed",
          message: `Refusing to write: a canary must not delete rows (${deleteCount}).`
        };
      }

      const insertCount = plan.items.filter((item) => item.operation === "insert").length;
      const updateCount = plan.items.filter((item) => item.operation === "update").length;
      const writeCount = insertCount + updateCount;

      if (writeCount > maxRows) {
        await client.query("rollback");
        return {
          ok: false,
          code: "row_bound_exceeded",
          message: `Refusing to write: canary would write ${writeCount} rows, over the bound of ${maxRows}.`
        };
      }

      if (
        input.expectedWrite &&
        (insertCount !== input.expectedWrite.insert || updateCount !== input.expectedWrite.update)
      ) {
        await client.query("rollback");
        return {
          ok: false,
          code: "diff_drift",
          message: `Refusing to write: diff drifted from review (expected ${input.expectedWrite.insert}i/${input.expectedWrite.update}u, got ${insertCount}i/${updateCount}u).`
        };
      }

      const tableSpecByName = indexTableSpecs(input.target);
      const items: AppliedCanaryItem[] = [];

      for (const planItem of plan.items) {
        const tableSpec = tableSpecByName.get(planItem.targetTable);
        if (!tableSpec) {
          // The planner only emits items for configured tables; a missing spec
          // here would be a logic error, so fail closed rather than write blind.
          await client.query("rollback");
          return {
            ok: false,
            code: "incompatible_diff",
            message: `Refusing to write: no target table spec for "${planItem.targetTable}".`
          };
        }

        const qualified = parseTableName(tableSpec.table);
        const payload = planItem.payload;
        const keys = pickKeys(payload, tableSpec.upsertKeys);
        const columns = Object.keys(payload);

        if (planItem.operation === "no_op") {
          items.push({
            targetTable: planItem.targetTable,
            operation: "no_op",
            recordKey: planItem.recordKey,
            idempotencyKey: planItem.idempotencyKey,
            keys,
            columns,
            priorState: null
          });
          continue;
        }

        if (planItem.operation === "insert") {
          await insertRow(client, qualified, columns, payload);
          items.push({
            targetTable: planItem.targetTable,
            operation: "insert",
            recordKey: planItem.recordKey,
            idempotencyKey: planItem.idempotencyKey,
            keys,
            columns,
            priorState: null
          });
          continue;
        }

        // update: capture prior state for the columns we are about to change,
        // then apply.
        const priorState = await selectRow(client, qualified, tableSpec.upsertKeys, keys, columns);
        await updateRow(client, qualified, tableSpec.upsertKeys, columns, payload);
        items.push({
          targetTable: planItem.targetTable,
          operation: "update",
          recordKey: planItem.recordKey,
          idempotencyKey: planItem.idempotencyKey,
          keys,
          columns,
          priorState
        });
      }

      await client.query("commit");
      return {
        ok: true,
        wroteToTarget: writeCount > 0,
        environment: "staging",
        counts: {
          insert: insertCount,
          update: updateCount,
          noOp: plan.items.length - writeCount,
          writeCount
        },
        items
      };
    } catch (error) {
      await client.query("rollback");
      throw error;
    }
  });
}

/**
 * Reverse a previously applied canary: delete inserted rows and restore updated
 * rows to their captured prior state. Idempotent — re-running after completion
 * is a no-op. Also staging-gated.
 */
export async function rollbackPostgresStagingCanary(
  input: RollbackPostgresStagingCanaryInput
): Promise<RollbackPostgresStagingCanaryResult> {
  return withClient(input, async (client) => {
    await client.query("begin");
    await client.query("set local statement_timeout = '15s'");
    try {
      if (!(await input.proveStaging(client))) {
        await client.query("rollback");
        throw new Error("Refusing to roll back: the target connection was not proven to be staging.");
      }

      let deletedInserts = 0;
      let restoredUpdates = 0;

      for (const item of input.items) {
        const qualified = parseTableName(item.targetTable);
        const keyColumns = Object.keys(item.keys);

        if (item.operation === "insert") {
          const deleted = await deleteRow(client, qualified, keyColumns, item.keys);
          deletedInserts += deleted;
        } else if (item.operation === "update" && item.priorState) {
          const restored = await restoreRow(
            client,
            qualified,
            keyColumns,
            item.keys,
            item.priorState
          );
          restoredUpdates += restored;
        }
      }

      await client.query("commit");
      return { ok: true, reverted: { deletedInserts, restoredUpdates } };
    } catch (error) {
      await client.query("rollback");
      throw error;
    }
  });
}

async function withClient<T>(
  input: { client?: PgClientLike; connectionString?: string },
  run: (client: PgClientLike) => Promise<T>
): Promise<T> {
  if (!input.client && !input.connectionString) {
    throw new Error("Staging canary requires a server-side connection string or client.");
  }
  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Staging canary client could not be initialized.");
  }
  if (ownedClient) {
    await ownedClient.connect();
  }
  try {
    return await run(client);
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

function indexTableSpecs(target: TargetProjectSpec): Map<string, TargetTableSpec> {
  const map = new Map<string, TargetTableSpec>();
  for (const tableSpec of target.shipment.tables) {
    map.set(parseTableName(tableSpec.table).displayName, tableSpec);
  }
  return map;
}

function pickKeys(payload: Record<string, unknown>, upsertKeys: string[]): Record<string, unknown> {
  return Object.fromEntries(upsertKeys.map((key) => [key, payload[key]]));
}

async function insertRow(
  client: PgClientLike,
  qualified: QualifiedTableName,
  columns: string[],
  payload: Record<string, unknown>
): Promise<void> {
  const placeholders = columns.map((_, index) => `$${index + 1}`);
  await client.query(
    `
      insert into ${quoteIdentifier(qualified.schema)}.${quoteIdentifier(qualified.table)}
        (${columns.map(quoteIdentifier).join(", ")})
      values (${placeholders.join(", ")})
    `,
    columns.map((column) => payload[column])
  );
}

async function updateRow(
  client: PgClientLike,
  qualified: QualifiedTableName,
  upsertKeys: string[],
  columns: string[],
  payload: Record<string, unknown>
): Promise<void> {
  const setColumns = columns.filter((column) => !upsertKeys.includes(column));
  if (setColumns.length === 0) {
    return;
  }
  const values: unknown[] = [];
  const setClause = setColumns
    .map((column) => {
      values.push(payload[column]);
      return `${quoteIdentifier(column)} = $${values.length}`;
    })
    .join(", ");
  const whereClause = upsertKeys
    .map((key) => {
      values.push(payload[key]);
      return `${quoteIdentifier(key)} = $${values.length}`;
    })
    .join(" and ");

  await client.query(
    `
      update ${quoteIdentifier(qualified.schema)}.${quoteIdentifier(qualified.table)}
      set ${setClause}
      where ${whereClause}
    `,
    values
  );
}

async function selectRow(
  client: PgClientLike,
  qualified: QualifiedTableName,
  upsertKeys: string[],
  keys: Record<string, unknown>,
  columns: string[]
): Promise<Record<string, unknown> | null> {
  const selected = [...new Set([...columns, ...upsertKeys])];
  const values: unknown[] = [];
  const whereClause = upsertKeys
    .map((key) => {
      values.push(keys[key]);
      return `${quoteIdentifier(key)} = $${values.length}`;
    })
    .join(" and ");

  const result = await client.query<Record<string, unknown>>(
    `
      select ${selected.map(quoteIdentifier).join(", ")}
      from ${quoteIdentifier(qualified.schema)}.${quoteIdentifier(qualified.table)}
      where ${whereClause}
      limit 1
    `,
    values
  );
  return result.rows[0] ?? null;
}

async function deleteRow(
  client: PgClientLike,
  qualified: QualifiedTableName,
  keyColumns: string[],
  keys: Record<string, unknown>
): Promise<number> {
  const values: unknown[] = [];
  const whereClause = keyColumns
    .map((key) => {
      values.push(keys[key]);
      return `${quoteIdentifier(key)} = $${values.length}`;
    })
    .join(" and ");

  const result = await client.query(
    `
      delete from ${quoteIdentifier(qualified.schema)}.${quoteIdentifier(qualified.table)}
      where ${whereClause}
    `,
    values
  );
  return result.rowCount ?? 0;
}

async function restoreRow(
  client: PgClientLike,
  qualified: QualifiedTableName,
  keyColumns: string[],
  keys: Record<string, unknown>,
  priorState: Record<string, unknown>
): Promise<number> {
  const setColumns = Object.keys(priorState).filter((column) => !keyColumns.includes(column));
  if (setColumns.length === 0) {
    return 0;
  }
  const values: unknown[] = [];
  const setClause = setColumns
    .map((column) => {
      values.push(priorState[column]);
      return `${quoteIdentifier(column)} = $${values.length}`;
    })
    .join(", ");
  const whereClause = keyColumns
    .map((key) => {
      values.push(keys[key]);
      return `${quoteIdentifier(key)} = $${values.length}`;
    })
    .join(" and ");

  const result = await client.query(
    `
      update ${quoteIdentifier(qualified.schema)}.${quoteIdentifier(qualified.table)}
      set ${setClause}
      where ${whereClause}
    `,
    values
  );
  return result.rowCount ?? 0;
}
