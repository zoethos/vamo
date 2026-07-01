import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import { Client, type QueryResult } from "pg";

import type { ProductionInboxPackage } from "../../../core/src/shipment-package.js";
import { buildProductionInboxPackage } from "../../../core/src/shipment-package.js";
import type { StagedCandidate } from "../../../core/src/pipeline-runner.js";
import { sampleProgressiveRunSnapshot } from "../../../core/src/progressive-read-model.js";
import type { PgClientLike } from "../src/postgres-dry-run.js";
import { deliverPostgresProductionInboxPackage } from "../src/postgres-production-inbox.js";

const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;
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

const report = sampleProgressiveRunSnapshot.entries[0]?.report;
if (!report) {
  throw new Error("sample progressive report missing");
}
const sampleReport = report;

describe("production inbox guard (no database)", () => {
  it("refuses when caller-side production proof fails before any insert", async () => {
    const fake = new FakeClient();
    const result = await deliverPostgresProductionInboxPackage({
      client: fake,
      package: packageForTest(),
      proveProduction: () => false
    });

    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.code, "production_not_proven");
    assert.ok(!fake.sql.some((sql) => /insert\s+into/i.test(sql)));
  });

  it("refuses targets that still carry staging canary state", async () => {
    const fakeRole = new FakeClient({ hasCanaryRole: true });
    const roleResult = await deliverPostgresProductionInboxPackage({
      client: fakeRole,
      package: packageForTest(),
      proveProduction: () => true
    });
    assert.equal(roleResult.ok, false);
    if (!roleResult.ok) assert.equal(roleResult.code, "staging_canary_role_present");

    const fakeSentinel = new FakeClient({ sentinelValue: "staging" });
    const sentinelResult = await deliverPostgresProductionInboxPackage({
      client: fakeSentinel,
      package: packageForTest(),
      proveProduction: () => true
    });
    assert.equal(sentinelResult.ok, false);
    if (!sentinelResult.ok) assert.equal(sentinelResult.code, "staging_guard_present");
  });
});

describe(
  "postgres production inbox delivery",
  { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for production-inbox smoke." },
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

    it("delivers a package as the inbox writer, computes checksums in SQL, and Vamo applies it", async () => {
      const pkg = packageForTest("production-inbox:test:approval:11");

      await client.query("set role confluendo_inbox_writer");
      let delivered;
      try {
        delivered = await deliverPostgresProductionInboxPackage({
          client,
          package: pkg,
          proveProduction: () => true
        });
      } finally {
        await client.query("reset role");
      }
      assert.equal(delivered.ok, true);
      if (!delivered.ok) return;
      assert.equal(delivered.wroteToInbox, true);
      assert.equal(delivered.itemCount, 2);

      const checksumRows = await client.query<{ package_checksum: string; computed_checksum: string }>(
        `
          select s.checksum as package_checksum,
                 encode(
                   extensions.digest(
                     convert_to(
                       string_agg(i.item_key || ':' || i.payload_checksum, E'\n' order by i.item_key),
                       'UTF8'
                     ),
                     'sha256'
                   ),
                   'hex'
                 ) as computed_checksum
          from confluendo_inbox.shipments s
          join confluendo_inbox.shipment_items i on i.package_id = s.package_id
          where s.package_id = $1
          group by s.package_id, s.checksum
        `,
        [pkg.packageId]
      );
      assert.equal(checksumRows.rows[0]?.package_checksum, checksumRows.rows[0]?.computed_checksum);

      const applied = await applyPackage(client, pkg.packageId);
      assert.equal(applied.status, "consumer_applied");
      assert.equal(applied.applied, 2);
      assert.equal(await canonicalCount(client), 1);

      await client.query("set role confluendo_inbox_writer");
      try {
        const second = await deliverPostgresProductionInboxPackage({
          client,
          package: pkg,
          proveProduction: () => true
        });
        assert.equal(second.ok, true);
        if (second.ok) {
          assert.equal(second.wroteToInbox, false);
          assert.equal(second.idempotent, true);
        }
      } finally {
        await client.query("reset role");
      }
    });

    it("refuses a production inbox connection that still has the staging canary sentinel", async () => {
      await client.query("create schema confluendo_guard");
      await client.query(
        "create table confluendo_guard.environment_sentinel (key text primary key, value text not null)"
      );
      await client.query(
        "insert into confluendo_guard.environment_sentinel (key, value) values ('environment', 'staging')"
      );

      const result = await deliverPostgresProductionInboxPackage({
        client,
        package: packageForTest("production-inbox:test:approval:12"),
        proveProduction: () => true
      });
      assert.equal(result.ok, false);
      if (!result.ok) assert.equal(result.code, "staging_guard_present");
    });
  }
);

class FakeClient implements PgClientLike {
  readonly sql: string[] = [];

  constructor(private readonly opts: { hasCanaryRole?: boolean; sentinelValue?: string } = {}) {}

  async query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string
  ): Promise<QueryResult<T>> {
    this.sql.push(sql.trim());
    if (sql.includes("pg_roles")) {
      return this.result<T>([{ exists: this.opts.hasCanaryRole === true }]);
    }
    if (sql.includes("to_regclass('confluendo_guard.environment_sentinel')")) {
      return this.result<T>([{ table_name: this.opts.sentinelValue ? "confluendo_guard.environment_sentinel" : null }]);
    }
    if (sql.includes("as checksum")) {
      return this.result<T>([{ checksum: "sql-computed-checksum" }]);
    }
    if (sql.includes("from confluendo_inbox.shipments")) {
      return this.result([]);
    }
    return this.result<T>([]);
  }

  private result<T extends Record<string, unknown>>(rows: Record<string, unknown>[]): QueryResult<T> {
    return { rows: rows as T[], rowCount: rows.length, command: "SELECT", oid: 0, fields: [] };
  }
}

function packageForTest(packageId = "production-inbox:test:approval:10"): ProductionInboxPackage {
  return buildProductionInboxPackage({
    packageId,
    consumerKey: "vamo",
    runReport: sampleReport,
    candidates: [candidate()],
    approvedBy: "supabase:user-1",
    approvalReason: "production inbox smoke"
  });
}

function candidate(): StagedCandidate {
  return {
    recordKey: "fsq_colosseum",
    sourceLineNumber: 1,
    sourceCursor: 1,
    targetProject: "vamo",
    targetProfile: "place-intelligence",
    sourceScope: { geography: "rome-italy", category: "poi" },
    payload: {
      location_canonicals: {
        canonical_key: "fsq-colosseum",
        display_name: "Colosseum",
        name_norm: "colosseum",
        feature_type: "poi",
        country_code: "IT",
        admin1: "Lazio",
        latitude: 41.8902,
        longitude: 12.4922,
        source_provider: "fsq_os_places",
        source_place_id: "fsq_colosseum",
        source_rank: 10,
        attribution: "FSQ Open Source Places",
        confidence: 0.95,
        promotion_state: "seeded"
      },
      location_source_refs: {
        canonical_key: "fsq-colosseum",
        provider: "fsq_os_places",
        source_place_id: "fsq_colosseum",
        source_payload_hash: "payload-hash",
        attribution: "FSQ Open Source Places",
        fetched_at: "2026-07-01T10:00:00.000Z"
      }
    }
  };
}

async function cleanup(client: Client): Promise<void> {
  await client.query("reset role");
  await client.query("drop schema if exists confluendo_guard cascade");
  await client.query("drop schema if exists confluendo_inbox cascade");
  await client.query("drop function if exists public.promote_location_aliases(integer) cascade");
  await client.query("drop table if exists public.location_observations cascade");
  await client.query("drop table if exists public.location_visual_cache cascade");
  await client.query("drop table if exists public.location_resolution_cache cascade");
  await client.query("drop table if exists public.location_aliases cascade");
  await client.query("drop table if exists public.location_source_refs cascade");
  await client.query("drop table if exists public.location_canonicals cascade");
  await client.query("drop table if exists public.location_provider_policies cascade");
  await client.query("drop table if exists public.trips cascade");
  await client.query("drop schema if exists auth cascade");
  // Roles are cluster-level and the disposable database container is removed
  // after the suite. Leaving them in place avoids role-drop cleanup stalls while
  // the migrations still reassert least-privilege flags idempotently.
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

async function applyPackage(
  client: Client,
  packageId: string
): Promise<{ applied: number; skipped: number; rejected: number; status: string }> {
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
