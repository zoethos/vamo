import { Client } from "pg";

import type { ProductionInboxPackage } from "../../../core/src/shipment-package.js";
import type { PgClientLike } from "./postgres-dry-run.js";

export type ProductionInboxDeliveryBlockCode =
  | "production_not_proven"
  | "staging_guard_present"
  | "staging_canary_role_present"
  | "duplicate_item_key"
  | "checksum_mismatch"
  | "target_query_failed";

export type ProductionInboxDeliveryResult =
  | {
      ok: true;
      packageId: string;
      checksum: string;
      itemCount: number;
      wroteToInbox: boolean;
      idempotent: boolean;
    }
  | {
      ok: false;
      code: ProductionInboxDeliveryBlockCode;
      message: string;
    };

export interface DeliverPostgresProductionInboxInput {
  package: ProductionInboxPackage;
  connectionString?: string;
  client?: PgClientLike;
  proveProduction?: () => boolean | Promise<boolean>;
}

interface ExistingShipmentRow extends Record<string, unknown> {
  checksum: string;
  status: string;
}

interface ChecksumRow extends Record<string, unknown> {
  checksum: string;
}

const STATEMENT_TIMEOUT = "5s";

export async function deliverPostgresProductionInboxPackage(
  input: DeliverPostgresProductionInboxInput
): Promise<ProductionInboxDeliveryResult> {
  if (!input.client && !input.connectionString) {
    throw new Error("Production inbox delivery requires a server-side connection string or client.");
  }
  const duplicateItemKey = firstDuplicate(input.package.items.map((item) => item.itemKey));
  if (duplicateItemKey) {
    return {
      ok: false,
      code: "duplicate_item_key",
      message: `Production inbox package has duplicate item_key "${duplicateItemKey}".`
    };
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Production inbox client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    await client.query("begin");
    await client.query(`set local statement_timeout = '${STATEMENT_TIMEOUT}'`);

    const callerProof = input.proveProduction ? await input.proveProduction() : true;
    if (!callerProof) {
      await client.query("rollback");
      return {
        ok: false,
        code: "production_not_proven",
        message: "Caller-side production proof failed; no inbox write was attempted."
      };
    }

    const proof = await proveProductionTarget(client);
    if (!proof.ok) {
      await client.query("rollback");
      return proof;
    }

    const itemsJson = JSON.stringify(input.package.items);
    const checksum = await computeIncomingPackageChecksum(client, itemsJson);

    const existing = await client.query<ExistingShipmentRow>(
      `
        select checksum, status
        from confluendo_inbox.shipments
        where package_id = $1
        for update
      `,
      [input.package.packageId]
    );
    const existingRow = existing.rows[0];
    if (existingRow) {
      await client.query("commit");
      if (existingRow.checksum === checksum) {
        return {
          ok: true,
          packageId: input.package.packageId,
          checksum,
          itemCount: input.package.items.length,
          wroteToInbox: false,
          idempotent: true
        };
      }
      return {
        ok: false,
        code: "checksum_mismatch",
        message:
          `Package ${input.package.packageId} already exists with checksum ${existingRow.checksum}; ` +
          `incoming checksum is ${checksum}.`
      };
    }

    await client.query(
      `
        insert into confluendo_inbox.shipments (
          package_id,
          consumer_key,
          target_environment,
          schema_contract,
          status,
          checksum,
          source_manifest,
          attribution_manifest,
          diff_summary,
          approved_by,
          approval_reason
        ) values (
          $1,
          $2,
          'production',
          $3,
          'production_inbox_delivered',
          $4,
          $5::jsonb,
          $6::jsonb,
          $7::jsonb,
          $8,
          $9
        )
      `,
      [
        input.package.packageId,
        input.package.consumerKey,
        input.package.schemaContract,
        checksum,
        JSON.stringify(input.package.sourceManifest),
        JSON.stringify(input.package.attributionManifest),
        JSON.stringify(input.package.diffSummary),
        input.package.approvedBy,
        input.package.approvalReason
      ]
    );

    const inserted = await client.query<{ item_key: string }>(
      `
        insert into confluendo_inbox.shipment_items (
          package_id,
          item_key,
          target_table,
          operation,
          payload,
          payload_checksum
        )
        select
          $1,
          item->>'itemKey',
          item->>'targetTable',
          item->>'operation',
          (item->'payload')::jsonb,
          encode(
            extensions.digest(convert_to((item->'payload')::jsonb::text, 'UTF8'), 'sha256'),
            'hex'
          )
        from jsonb_array_elements($2::jsonb) item
        returning item_key
      `,
      [input.package.packageId, itemsJson]
    );
    if (inserted.rows.length !== input.package.items.length) {
      await client.query("rollback");
      return {
        ok: false,
        code: "target_query_failed",
        message: `Inserted ${inserted.rows.length} item(s), expected ${input.package.items.length}.`
      };
    }

    await client.query("commit");
    return {
      ok: true,
      packageId: input.package.packageId,
      checksum,
      itemCount: input.package.items.length,
      wroteToInbox: true,
      idempotent: false
    };
  } catch (error) {
    await client.query("rollback");
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

async function proveProductionTarget(
  client: PgClientLike
): Promise<{ ok: true } | { ok: false; code: ProductionInboxDeliveryBlockCode; message: string }> {
  const canaryRole = await client.query<{ exists: boolean }>(
    "select exists (select 1 from pg_roles where rolname = 'vamo_canary_app') as exists"
  );
  if (canaryRole.rows[0]?.exists === true) {
    return {
      ok: false,
      code: "staging_canary_role_present",
      message: "The staging canary role vamo_canary_app exists on this target; refusing production delivery."
    };
  }

  const sentinel = await client.query<{ table_name: string | null }>(
    "select to_regclass('confluendo_guard.environment_sentinel')::text as table_name"
  );
  if (sentinel.rows[0]?.table_name) {
    return {
      ok: false,
      code: "staging_guard_present",
      message: "The staging environment sentinel table exists on this target; refusing production delivery."
    };
  }

  return { ok: true };
}

async function computeIncomingPackageChecksum(
  client: PgClientLike,
  itemsJson: string
): Promise<string> {
  const result = await client.query<ChecksumRow>(
    `
      with incoming as (
        select
          item->>'itemKey' as item_key,
          encode(
            extensions.digest(convert_to((item->'payload')::jsonb::text, 'UTF8'), 'sha256'),
            'hex'
          ) as payload_checksum
        from jsonb_array_elements($1::jsonb) item
      )
      select encode(
               extensions.digest(
                 convert_to(
                   coalesce(string_agg(item_key || ':' || payload_checksum, E'\n' order by item_key), ''),
                   'UTF8'
                 ),
                 'sha256'
               ),
               'hex'
             ) as checksum
      from incoming
    `,
    [itemsJson]
  );
  const checksum = result.rows[0]?.checksum;
  if (!checksum) {
    throw new Error("Target Postgres did not return a package checksum.");
  }
  return checksum;
}

function firstDuplicate(values: string[]): string | undefined {
  const seen = new Set<string>();
  for (const value of values) {
    if (seen.has(value)) {
      return value;
    }
    seen.add(value);
  }
  return undefined;
}
