/**
 * Vamo-owned production inbox consumer apply adapter (IP-18.6.6).
 *
 * Invokes confluendo_inbox.apply_confluendo_shipment only. Never writes Vamo
 * product tables directly from TypeScript and never delivers packages.
 */

import { Client } from "pg";

import type { PgClientLike } from "./postgres-dry-run.js";

export type ProductionInboxApplyBlockCode =
  | "apply_not_proven"
  | "staging_guard_present"
  | "staging_canary_role_present"
  | "package_not_found"
  | "target_query_failed";

export interface ProductionInboxApplyItemPreflight {
  itemKey: string;
  targetTable: string;
  operation: string;
  applyStatus: string;
  applyError: string | null;
}

export interface ProductionInboxApplyPreflight {
  packageId: string;
  shipmentStatus: string;
  checksum: string;
  itemCount: number;
  pendingItemCount: number;
  targetTables: string[];
  items: ProductionInboxApplyItemPreflight[];
  latestApplyLogResult: string | null;
  latestApplyLogDetail: string | null;
}

export type ReadProductionInboxApplyPreflightResult =
  | { ok: true; preflight: ProductionInboxApplyPreflight }
  | { ok: false; code: ProductionInboxApplyBlockCode; message: string };

export interface ProductionInboxApplyResultPayload {
  packageId: string;
  applied: number;
  skipped: number;
  rejected: number;
  status: string;
  error?: string;
}

export type ApplyPostgresProductionInboxPackageResult =
  | { ok: true; result: ProductionInboxApplyResultPayload }
  | { ok: false; code: ProductionInboxApplyBlockCode; message: string; result?: ProductionInboxApplyResultPayload };

export interface ReadProductionInboxApplyPreflightInput {
  packageId: string;
  connectionString?: string;
  client?: PgClientLike;
  proveApply?: () => boolean | Promise<boolean>;
}

export interface ApplyPostgresProductionInboxPackageInput {
  packageId: string;
  approvedBy: string;
  approvalReason: string;
  connectionString?: string;
  client?: PgClientLike;
  proveApply?: () => boolean | Promise<boolean>;
}

interface ShipmentPreflightRow extends Record<string, unknown> {
  packageId: string;
  shipmentStatus: string;
  checksum: string;
  itemCount: string;
  pendingItemCount: string;
}

interface ItemPreflightRow extends Record<string, unknown> {
  itemKey: string;
  targetTable: string;
  operation: string;
  applyStatus: string;
  applyError: string | null;
}

interface ApplyLogRow extends Record<string, unknown> {
  result: string;
  detail: string | null;
}

interface ApplyResultRow extends Record<string, unknown> {
  result: ProductionInboxApplyResultPayload;
}

const STATEMENT_TIMEOUT = "15s";

export async function readPostgresProductionInboxApplyPreflight(
  input: ReadProductionInboxApplyPreflightInput
): Promise<ReadProductionInboxApplyPreflightResult> {
  const packageId = input.packageId.trim();
  if (!packageId) {
    return { ok: false, code: "package_not_found", message: "packageId is required." };
  }

  if (!input.client && !input.connectionString) {
    throw new Error("Production inbox apply preflight requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Production inbox apply client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    const callerProof = input.proveApply ? await input.proveApply() : true;
    if (!callerProof) {
      return {
        ok: false,
        code: "apply_not_proven",
        message: "Caller-side production apply proof failed; no inbox read was attempted."
      };
    }

    const proof = await proveApplyTarget(client);
    if (!proof.ok) {
      return proof;
    }

    return await withStatementTimeout(client, async () => {
      const shipment = await client.query<ShipmentPreflightRow>(
        `
          select
            s.package_id as "packageId",
            s.status as "shipmentStatus",
            s.checksum,
            count(i.item_key)::text as "itemCount",
            count(*) filter (where i.apply_status = 'pending')::text as "pendingItemCount"
          from confluendo_inbox.shipments s
          left join confluendo_inbox.shipment_items i on i.package_id = s.package_id
          where s.package_id = $1
          group by s.package_id, s.status, s.checksum
        `,
        [packageId]
      );
      const row = shipment.rows[0];
      if (!row) {
        return {
          ok: false,
          code: "package_not_found",
          message: `Production inbox package ${packageId} was not found.`
        };
      }

      const items = await client.query<ItemPreflightRow>(
        `
          select
            item_key as "itemKey",
            target_table as "targetTable",
            operation,
            apply_status as "applyStatus",
            apply_error as "applyError"
          from confluendo_inbox.shipment_items
          where package_id = $1
          order by item_key asc
        `,
        [packageId]
      );

      const applyLog = await client.query<ApplyLogRow>(
        `
          select result, detail
          from confluendo_inbox.apply_log
          where package_id = $1
          order by applied_at desc, id desc
          limit 1
        `,
        [packageId]
      );

      const targetTables = [...new Set(items.rows.map((item) => item.targetTable))].sort();

      return {
        ok: true,
        preflight: {
          packageId: row.packageId,
          shipmentStatus: row.shipmentStatus,
          checksum: row.checksum,
          itemCount: Number.parseInt(row.itemCount, 10),
          pendingItemCount: Number.parseInt(row.pendingItemCount, 10),
          targetTables,
          items: items.rows.map((item) => ({
            itemKey: item.itemKey,
            targetTable: item.targetTable,
            operation: item.operation,
            applyStatus: item.applyStatus,
            applyError: item.applyError
          })),
          latestApplyLogResult: applyLog.rows[0]?.result ?? null,
          latestApplyLogDetail: applyLog.rows[0]?.detail ?? null
        }
      };
    });
  } catch (error) {
    return {
      ok: false,
      code: "target_query_failed",
      message: error instanceof Error ? error.message : String(error)
    };
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

export async function applyPostgresProductionInboxPackage(
  input: ApplyPostgresProductionInboxPackageInput
): Promise<ApplyPostgresProductionInboxPackageResult> {
  const packageId = input.packageId.trim();
  const approvedBy = input.approvedBy.trim();
  const approvalReason = input.approvalReason.trim();

  if (!packageId) {
    return { ok: false, code: "package_not_found", message: "packageId is required." };
  }

  if (!input.client && !input.connectionString) {
    throw new Error("Production inbox apply requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Production inbox apply client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    const callerProof = input.proveApply ? await input.proveApply() : true;
    if (!callerProof) {
      return {
        ok: false,
        code: "apply_not_proven",
        message: "Caller-side production apply proof failed; no inbox apply was attempted."
      };
    }

    const proof = await proveApplyTarget(client);
    if (!proof.ok) {
      return proof;
    }

    return await withStatementTimeout(client, async () => {
      const applied = await client.query<ApplyResultRow>(
        `
          select confluendo_inbox.apply_confluendo_shipment($1, $2, $3) as result
        `,
        [packageId, approvedBy, approvalReason]
      );
      const result = normalizeApplyResult(applied.rows[0]?.result, packageId);
      if (!result) {
        return {
          ok: false,
          code: "target_query_failed",
          message: "apply_confluendo_shipment returned no result payload."
        };
      }

      if (result.status === "consumer_apply_failed" || result.rejected > 0) {
        return {
          ok: false,
          code: "target_query_failed",
          message: result.error ?? "Consumer apply failed.",
          result
        };
      }

      return { ok: true, result };
    });
  } catch (error) {
    return {
      ok: false,
      code: "target_query_failed",
      message: error instanceof Error ? error.message : String(error)
    };
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

async function proveApplyTarget(
  client: PgClientLike
): Promise<{ ok: true } | { ok: false; code: ProductionInboxApplyBlockCode; message: string }> {
  const canaryRole = await client.query<{ exists: boolean }>(
    "select exists (select 1 from pg_roles where rolname = 'vamo_canary_app') as exists"
  );
  if (canaryRole.rows[0]?.exists === true) {
    return {
      ok: false,
      code: "staging_canary_role_present",
      message: "The staging canary role vamo_canary_app exists on this target; refusing production apply."
    };
  }

  const sentinel = await client.query<{ table_name: string | null }>(
    "select to_regclass('confluendo_guard.environment_sentinel')::text as table_name"
  );
  if (sentinel.rows[0]?.table_name) {
    return {
      ok: false,
      code: "staging_guard_present",
      message: "The staging environment sentinel table exists on this target; refusing production apply."
    };
  }

  return { ok: true };
}

async function withStatementTimeout<T>(client: PgClientLike, run: () => Promise<T>): Promise<T> {
  await client.query("begin");
  try {
    await client.query(`set local statement_timeout = '${STATEMENT_TIMEOUT}'`);
    const result = await run();
    await client.query("commit");
    return result;
  } catch (error) {
    await client.query("rollback");
    throw error;
  }
}

function normalizeApplyResult(
  value: unknown,
  packageId: string
): ProductionInboxApplyResultPayload | undefined {
  if (!value || typeof value !== "object") {
    return undefined;
  }
  const record = value as Record<string, unknown>;
  return {
    packageId: typeof record.package_id === "string" ? record.package_id : packageId,
    applied: typeof record.applied === "number" ? record.applied : Number(record.applied ?? 0),
    skipped: typeof record.skipped === "number" ? record.skipped : Number(record.skipped ?? 0),
    rejected: typeof record.rejected === "number" ? record.rejected : Number(record.rejected ?? 0),
    status: typeof record.status === "string" ? record.status : "unknown",
    error: typeof record.error === "string" ? record.error : undefined
  };
}
