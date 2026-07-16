import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import { Client } from "pg";

import {
  resetDisposableTestDatabase,
  resolveDisposableTestDatabaseUrl
} from "./disposable-test-database.js";

const databaseUrl = resolveDisposableTestDatabaseUrl(process.env.INGESTION_TEST_DATABASE_URL);
const placeIntelligenceSql = readFileSync(
  "../../../supabase/migrations/20260625155733_place_intelligence_cache.sql",
  "utf8"
);
const confluendoInboxSql = readFileSync(
  "../../../supabase/migrations/20260701100233_confluendo_inbox.sql",
  "utf8"
);
const writerDigestGrantSql = readFileSync(
  "../../../supabase/migrations/20260701121500_confluendo_inbox_writer_digest_usage.sql",
  "utf8"
);

describe(
  "Vamo Confluendo production inbox migration",
  { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for Vamo production inbox DB smoke." },
  () => {
    let client: Client;

    before(async () => {
      assert.ok(databaseUrl);
      client = new Client({ connectionString: databaseUrl });
      await client.connect();
    });

    after(async () => {
      await cleanup(client);
      await client.end();
    });

    beforeEach(async () => {
      await cleanup(client);
      await createSupabaseRoles(client);
      await createSupabaseAuthStub(client);
      await createVamoSchemaStub(client);
      await client.query("create schema if not exists extensions");
      await client.query("create extension if not exists pgcrypto with schema extensions");
      await client.query(placeIntelligenceSql);
      await client.query(confluendoInboxSql);
      await client.query(writerDigestGrantSql);
    });

    it("keeps the inbox writer isolated from product tables", async () => {
      assert.equal(
        await hasPrivilege(client, "confluendo_inbox_writer", "public.location_canonicals", "INSERT"),
        false
      );
      assert.equal(
        await hasPrivilege(client, "confluendo_inbox_writer", "public.location_canonicals", "UPDATE"),
        false
      );
      assert.equal(
        await hasPrivilege(client, "confluendo_inbox_writer", "public.location_canonicals", "SELECT"),
        false
      );
      assert.equal(
        await hasPrivilege(client, "confluendo_inbox_writer", "public.location_source_refs", "INSERT"),
        false
      );

      await client.query("set role confluendo_inbox_writer");
      try {
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
              diff_summary
            ) values (
              'least-privilege-package',
              'vamo',
              'production',
              'vamo-place-intelligence@1',
              'production_inbox_delivered',
              'checksum',
              '{}',
              '{}',
              '{}'
            )
          `
        );
        await client.query(
          `
            insert into confluendo_inbox.shipment_items (
              package_id,
              item_key,
              target_table,
              operation,
              payload,
              payload_checksum
            ) values (
              'least-privilege-package',
              'item-1',
              'location_canonicals',
              'upsert',
              '{"canonical_key":"demo"}',
              'checksum'
            )
          `
        );

        await assertPostgresCode(
          client.query("select count(*) from public.location_canonicals"),
          "42501"
        );
        await assertPostgresCode(
          client.query(
            `
              insert into public.location_canonicals (
                canonical_key,
                display_name,
                name_norm,
                source_provider,
                attribution
              ) values (
                'forbidden',
                'Forbidden',
                'forbidden',
                'fsq_os_places',
                'test'
              )
            `
          ),
          "42501"
        );
      } finally {
        await client.query("reset role");
      }
    });

    it("supports idempotent package delivery with checksum verification", async () => {
      const checksum = await packageChecksum(client, []);

      await client.query("set role confluendo_inbox_writer");
      try {
        const first = await idempotentShipmentInsert(client, "idempotent-package", checksum);
        const second = await idempotentShipmentInsert(client, "idempotent-package", checksum);
        const mismatch = await idempotentShipmentInsert(client, "idempotent-package", "wrong-checksum");

        assert.equal(first.rowCount, 1);
        assert.equal(second.rowCount, 1);
        assert.equal(mismatch.rowCount, 0);
      } finally {
        await client.query("reset role");
      }
    });

    it("applies a canonical and source reference package exactly once", async () => {
      await insertPlacePackage(client, "happy-package");

      const first = await applyPackage(client, "happy-package");
      assert.equal(first.status, "consumer_applied");
      assert.equal(first.applied, 2);
      assert.equal(first.skipped, 0);
      assert.equal(first.rejected, 0);

      const canonical = await client.query<{
        display_name: string;
        promotion_state: string;
        source_provider: string;
      }>(
        `
          select display_name, promotion_state, source_provider
          from public.location_canonicals
          where canonical_key = 'fsq:rome-colosseum'
        `
      );
      assert.equal(canonical.rowCount, 1);
      assert.equal(canonical.rows[0]?.display_name, "Colosseum");
      assert.equal(canonical.rows[0]?.promotion_state, "seeded");
      assert.equal(canonical.rows[0]?.source_provider, "fsq_os_places");

      const sourceRef = await client.query<{ count: string }>(
        `
          select count(*)::text as count
          from public.location_source_refs sr
          join public.location_canonicals lc on lc.id = sr.canonical_id
          where lc.canonical_key = 'fsq:rome-colosseum'
            and sr.provider = 'fsq_os_places'
            and sr.source_place_id = 'rome-colosseum'
        `
      );
      assert.equal(Number(sourceRef.rows[0]?.count), 1);

      const appliedItems = await client.query<{ apply_status: string }>(
        `
          select apply_status
          from confluendo_inbox.shipment_items
          where package_id = 'happy-package'
          order by item_key
        `
      );
      assert.deepEqual(
        appliedItems.rows.map((row) => row.apply_status),
        ["applied", "applied"]
      );

      const logBefore = await applyLogCount(client, "happy-package");
      const second = await applyPackage(client, "happy-package");
      const logAfter = await applyLogCount(client, "happy-package");

      assert.equal(second.status, "consumer_applied");
      assert.equal(second.applied, 0);
      assert.equal(second.skipped, 1);
      assert.equal(second.rejected, 0);
      assert.equal(logAfter, logBefore);
    });

    it("rejects checksum mismatch without product writes", async () => {
      await insertPlacePackage(client, "bad-checksum-package", {
        checksumOverride: "bad-package-checksum"
      });

      const result = await applyPackage(client, "bad-checksum-package");
      assert.equal(result.status, "consumer_apply_failed");
      assert.equal(result.error, "package_checksum_mismatch");
      assert.equal(await canonicalCount(client), 0);
    });

    it("rejects delete operations without product writes", async () => {
      await insertPlacePackage(client, "delete-package", {
        canonicalOperation: "delete"
      });

      const result = await applyPackage(client, "delete-package");
      assert.equal(result.status, "consumer_apply_failed");
      assert.equal(result.error, "delete_not_supported");
      assert.equal(await canonicalCount(client), 0);
    });

    it("rejects an unsupported schema contract without product writes", async () => {
      await insertPlacePackage(client, "wrong-contract-package", {
        schemaContract: "vamo-place-intelligence@999"
      });

      const result = await applyPackage(client, "wrong-contract-package");
      assert.equal(result.status, "consumer_apply_failed");
      assert.equal(result.error, "unsupported_schema_contract");
      assert.equal(await canonicalCount(client), 0);
    });

    it("rejects a non-production package without product writes", async () => {
      await insertPlacePackage(client, "staging-package", {
        targetEnvironment: "staging"
      });

      const result = await applyPackage(client, "staging-package");
      assert.equal(result.status, "consumer_apply_failed");
      assert.equal(result.error, "non_production_target");
      assert.equal(await canonicalCount(client), 0);
    });
  }
);

async function cleanup(client: Client): Promise<void> {
  await client.query("reset role");
  await resetDisposableTestDatabase(client, databaseUrl!, { schemas: ["confluendo_inbox"] });
  await resetDisposableTestDatabase(client, databaseUrl!, { functions: [{ schema: "public", name: "promote_location_aliases", arguments: "integer" }] });
  await resetDisposableTestDatabase(client, databaseUrl!, { tables: [{ schema: "public", name: "location_observations" }] });
  await resetDisposableTestDatabase(client, databaseUrl!, { tables: [{ schema: "public", name: "location_visual_cache" }] });
  await resetDisposableTestDatabase(client, databaseUrl!, { tables: [{ schema: "public", name: "location_resolution_cache" }] });
  await resetDisposableTestDatabase(client, databaseUrl!, { tables: [{ schema: "public", name: "location_aliases" }] });
  await resetDisposableTestDatabase(client, databaseUrl!, { tables: [{ schema: "public", name: "location_source_refs" }] });
  await resetDisposableTestDatabase(client, databaseUrl!, { tables: [{ schema: "public", name: "location_canonicals" }] });
  await resetDisposableTestDatabase(client, databaseUrl!, { tables: [{ schema: "public", name: "location_provider_policies" }] });
  await resetDisposableTestDatabase(client, databaseUrl!, { tables: [{ schema: "public", name: "trips" }] });
  await resetDisposableTestDatabase(client, databaseUrl!, { schemas: ["auth"] });
  // `confluendo_inbox_writer` is cluster-level. The disposable Postgres
  // container is removed after DB smokes, and the migration reasserts the role
  // flags idempotently before every test.
}

async function createSupabaseRoles(client: Client): Promise<void> {
  await client.query(`
    do $$
    begin
      if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
      end if;
      if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
      end if;
      if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin bypassrls;
      end if;
    end;
    $$
  `);
}

async function createSupabaseAuthStub(client: Client): Promise<void> {
  await client.query("create schema if not exists auth");
  await client.query("create table if not exists auth.users (id uuid primary key)");
}

async function createVamoSchemaStub(client: Client): Promise<void> {
  await client.query("create table if not exists public.trips (id uuid primary key)");
}

async function hasPrivilege(
  client: Client,
  role: string,
  relation: string,
  privilege: string
): Promise<boolean> {
  const result = await client.query<{ allowed: boolean }>(
    "select has_table_privilege($1, $2, $3) as allowed",
    [role, relation, privilege]
  );
  return result.rows[0]?.allowed ?? false;
}

async function idempotentShipmentInsert(
  client: Client,
  packageId: string,
  checksum: string
) {
  return client.query(
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
        diff_summary
      ) values (
        $1,
        'vamo',
        'production',
        'vamo-place-intelligence@1',
        'production_inbox_delivered',
        $2,
        '{}',
        '{}',
        '{}'
      )
      on conflict (package_id) do update
        set status = confluendo_inbox.shipments.status
        where confluendo_inbox.shipments.checksum = excluded.checksum
      returning package_id
    `,
    [packageId, checksum]
  );
}

interface InsertPackageOptions {
  checksumOverride?: string;
  canonicalOperation?: "upsert" | "delete";
  schemaContract?: string;
  targetEnvironment?: "staging" | "production";
}

async function insertPlacePackage(
  client: Client,
  packageId: string,
  options: InsertPackageOptions = {}
): Promise<void> {
  const canonicalPayload = {
    canonical_key: "fsq:rome-colosseum",
    display_name: "Colosseum",
    name_norm: "colosseum",
    feature_type: "landmark",
    country_code: "IT",
    admin1: "Lazio",
    latitude: 41.8902,
    longitude: 12.4922,
    source_provider: "fsq_os_places",
    source_place_id: "rome-colosseum",
    source_rank: 10,
    attribution: "Foursquare OS Places (Apache-2.0)",
    confidence: 0.95,
    promotion_state: "seeded"
  };
  const sourceRefPayload = {
    canonical_key: "fsq:rome-colosseum",
    provider: "fsq_os_places",
    source_place_id: "rome-colosseum",
    source_payload_hash: "payload-hash",
    attribution: "Foursquare OS Places (Apache-2.0)",
    fetched_at: "2026-07-01T10:00:00.000Z"
  };

  const items = [
    {
      itemKey: "location_canonicals:fsq:rome-colosseum",
      targetTable: "location_canonicals",
      operation: options.canonicalOperation ?? "upsert",
      payload: canonicalPayload,
      payloadChecksum: await payloadChecksum(client, canonicalPayload)
    },
    {
      itemKey: "location_source_refs:fsq_os_places:rome-colosseum",
      targetTable: "location_source_refs",
      operation: "upsert" as const,
      payload: sourceRefPayload,
      payloadChecksum: await payloadChecksum(client, sourceRefPayload)
    }
  ];
  const checksum = options.checksumOverride ?? (await packageChecksum(client, items));

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
        diff_summary
      ) values (
        $1,
        'vamo',
        $2,
        $3,
        'production_inbox_delivered',
        $4,
        '{"source":"fsq-os-places-sample"}',
        '{"attribution":"Foursquare OS Places (Apache-2.0)"}',
        '{"insert":2,"update":0,"delete":0}'
      )
    `,
    [
      packageId,
      options.targetEnvironment ?? "production",
      options.schemaContract ?? "vamo-place-intelligence@1",
      checksum
    ]
  );

  for (const item of items) {
    await client.query(
      `
        insert into confluendo_inbox.shipment_items (
          package_id,
          item_key,
          target_table,
          operation,
          payload,
          payload_checksum
        ) values ($1, $2, $3, $4, $5::jsonb, $6)
      `,
      [
        packageId,
        item.itemKey,
        item.targetTable,
        item.operation,
        JSON.stringify(item.payload),
        item.payloadChecksum
      ]
    );
  }
}

async function payloadChecksum(client: Client, payload: Record<string, unknown>): Promise<string> {
  const result = await client.query<{ checksum: string }>(
    `
      select encode(
        extensions.digest(convert_to($1::jsonb::text, 'UTF8'), 'sha256'),
        'hex'
      ) as checksum
    `,
    [JSON.stringify(payload)]
  );
  return result.rows[0]?.checksum ?? "";
}

async function packageChecksum(
  client: Client,
  items: Array<{ itemKey: string; payloadChecksum: string }>
): Promise<string> {
  const canonical = [...items]
    .sort((a, b) => a.itemKey.localeCompare(b.itemKey))
    .map((item) => `${item.itemKey}:${item.payloadChecksum}`)
    .join("\n");
  const result = await client.query<{ checksum: string }>(
    `
      select encode(
        extensions.digest(convert_to($1, 'UTF8'), 'sha256'),
        'hex'
      ) as checksum
    `,
    [canonical]
  );
  return result.rows[0]?.checksum ?? "";
}

async function applyPackage(
  client: Client,
  packageId: string
): Promise<{
  package_id: string;
  applied: number;
  skipped: number;
  rejected: number;
  status: string;
  error?: string;
}> {
  const result = await client.query<{ result: Record<string, unknown> }>(
    `
      select confluendo_inbox.apply_confluendo_shipment(
        $1,
        'vamo-operator',
        'disposable postgres smoke'
      ) as result
    `,
    [packageId]
  );
  return result.rows[0]?.result as Awaited<ReturnType<typeof applyPackage>>;
}

async function canonicalCount(client: Client): Promise<number> {
  const result = await client.query<{ count: string }>(
    "select count(*)::text as count from public.location_canonicals"
  );
  return Number(result.rows[0]?.count ?? 0);
}

async function applyLogCount(client: Client, packageId: string): Promise<number> {
  const result = await client.query<{ count: string }>(
    "select count(*)::text as count from confluendo_inbox.apply_log where package_id = $1",
    [packageId]
  );
  return Number(result.rows[0]?.count ?? 0);
}

async function assertPostgresCode(promise: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(promise, (error: unknown) => {
    return typeof error === "object" && error !== null && "code" in error && error.code === code;
  });
}
