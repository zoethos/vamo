/**
 * Read-only production inbox apply telemetry (IP-18.6.4).
 *
 * Polls Vamo-owned confluendo_inbox shipment and item apply status. Never
 * writes to the inbox, never touches product tables, and never invokes apply.
 */

import { Client } from "pg";

import type { PgClientLike } from "./postgres-dry-run.js";

export type ProductionInboxTelemetryBlockCode =
  | "telemetry_not_proven"
  | "staging_guard_present"
  | "staging_canary_role_present"
  | "target_query_failed";

export interface ProductionInboxPackageApplyTelemetry {
  packageId: string;
  shipmentStatus: string;
  checksum: string;
  appliedAt: string | null;
  itemCount: number;
  pendingItemCount: number;
  appliedItemCount: number;
  skippedItemCount: number;
  rejectedItemCount: number;
  latestApplyLogResult: string | null;
  latestApplyLogDetail: string | null;
}

export type ReadProductionInboxApplyTelemetryResult =
  | { ok: true; packages: ProductionInboxPackageApplyTelemetry[] }
  | { ok: false; code: ProductionInboxTelemetryBlockCode; message: string };

export interface ReadProductionInboxApplyTelemetryInput {
  packageIds: readonly string[];
  connectionString?: string;
  client?: PgClientLike;
  proveTelemetry?: () => boolean | Promise<boolean>;
}

interface ShipmentTelemetryRow extends Record<string, unknown> {
  packageId: string;
  shipmentStatus: string;
  checksum: string;
  appliedAt: string | Date | null;
  itemCount: string;
  pendingItemCount: string;
  appliedItemCount: string;
  skippedItemCount: string;
  rejectedItemCount: string;
}

interface ApplyLogRow extends Record<string, unknown> {
  packageId: string;
  result: string;
  detail: string | null;
}

const STATEMENT_TIMEOUT = "5s";

export async function readPostgresProductionInboxApplyTelemetry(
  input: ReadProductionInboxApplyTelemetryInput
): Promise<ReadProductionInboxApplyTelemetryResult> {
  const packageIds = [...new Set(input.packageIds.map((id) => id.trim()).filter(Boolean))];
  if (packageIds.length === 0) {
    return { ok: true, packages: [] };
  }

  if (!input.client && !input.connectionString) {
    throw new Error("Production inbox telemetry requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Production inbox telemetry client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    const callerProof = input.proveTelemetry ? await input.proveTelemetry() : true;
    if (!callerProof) {
      return {
        ok: false,
        code: "telemetry_not_proven",
        message: "Caller-side production telemetry proof failed; no inbox read was attempted."
      };
    }

    const proof = await proveTelemetryTarget(client);
    if (!proof.ok) {
      return proof;
    }

    await client.query(`set local statement_timeout = '${STATEMENT_TIMEOUT}'`);

    const shipments = await client.query<ShipmentTelemetryRow>(
      `
        select
          s.package_id as "packageId",
          s.status as "shipmentStatus",
          s.checksum,
          s.applied_at as "appliedAt",
          count(i.item_key)::text as "itemCount",
          count(*) filter (where i.apply_status = 'pending')::text as "pendingItemCount",
          count(*) filter (where i.apply_status = 'applied')::text as "appliedItemCount",
          count(*) filter (where i.apply_status = 'skipped')::text as "skippedItemCount",
          count(*) filter (where i.apply_status = 'rejected')::text as "rejectedItemCount"
        from confluendo_inbox.shipments s
        left join confluendo_inbox.shipment_items i on i.package_id = s.package_id
        where s.package_id = any($1::text[])
        group by s.package_id, s.status, s.checksum, s.applied_at
        order by s.package_id asc
      `,
      [packageIds]
    );

    const applyLogs = await client.query<ApplyLogRow>(
      `
        select distinct on (package_id)
          package_id as "packageId",
          result,
          detail
        from confluendo_inbox.apply_log
        where package_id = any($1::text[])
        order by package_id asc, applied_at desc, id desc
      `,
      [packageIds]
    );
    const applyLogByPackageId = new Map(applyLogs.rows.map((row) => [row.packageId, row]));

    return {
      ok: true,
      packages: shipments.rows.map((row) => ({
        packageId: row.packageId,
        shipmentStatus: row.shipmentStatus,
        checksum: row.checksum,
        appliedAt: toIsoString(row.appliedAt),
        itemCount: Number.parseInt(row.itemCount, 10),
        pendingItemCount: Number.parseInt(row.pendingItemCount, 10),
        appliedItemCount: Number.parseInt(row.appliedItemCount, 10),
        skippedItemCount: Number.parseInt(row.skippedItemCount, 10),
        rejectedItemCount: Number.parseInt(row.rejectedItemCount, 10),
        latestApplyLogResult: applyLogByPackageId.get(row.packageId)?.result ?? null,
        latestApplyLogDetail: applyLogByPackageId.get(row.packageId)?.detail ?? null
      }))
    };
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

async function proveTelemetryTarget(
  client: PgClientLike
): Promise<{ ok: true } | { ok: false; code: ProductionInboxTelemetryBlockCode; message: string }> {
  const canaryRole = await client.query<{ exists: boolean }>(
    "select exists (select 1 from pg_roles where rolname = 'vamo_canary_app') as exists"
  );
  if (canaryRole.rows[0]?.exists === true) {
    return {
      ok: false,
      code: "staging_canary_role_present",
      message: "The staging canary role vamo_canary_app exists on this target; refusing production telemetry."
    };
  }

  const sentinel = await client.query<{ table_name: string | null }>(
    "select to_regclass('confluendo_guard.environment_sentinel')::text as table_name"
  );
  if (sentinel.rows[0]?.table_name) {
    return {
      ok: false,
      code: "staging_guard_present",
      message: "The staging environment sentinel table exists on this target; refusing production telemetry."
    };
  }

  return { ok: true };
}

function toIsoString(value: string | Date | null): string | null {
  if (value instanceof Date) {
    return value.toISOString();
  }
  return typeof value === "string" ? value : null;
}
