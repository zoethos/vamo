import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { after, before, beforeEach, describe, it } from "node:test";
import { Client, type QueryResult } from "pg";

import type { ProductionInboxPackage } from "../../../core/src/shipment-package.js";
import { buildProductionInboxPackage } from "../../../core/src/shipment-package.js";
import type { StagedCandidate } from "../../../core/src/pipeline-runner.js";
import { sampleProgressiveRunSnapshot } from "../../../core/src/progressive-read-model.js";
import type { PgClientLike } from "../src/postgres-dry-run.js";
import { deliverPostgresProductionInboxPackage } from "../src/postgres-production-inbox.js";
import { readPostgresProductionInboxApplyTelemetry } from "../src/postgres-production-inbox-telemetry.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..", "..");
const telemetrySource = readFileSync(
  join(testDir, "..", "src", "postgres-production-inbox-telemetry.js"),
  "utf8"
);
const confluendoInboxSql = readFileSync(
  join(packageRoot, "..", "..", "..", "supabase", "migrations", "20260701100233_confluendo_inbox.sql"),
  "utf8"
);
const telemetryRoleSql = readFileSync(
  join(
    packageRoot,
    "..",
    "..",
    "..",
    "supabase",
    "migrations",
    "20260707120000_confluendo_inbox_telemetry_reader.sql"
  ),
  "utf8"
);
const placeIntelligenceSql = readFileSync(
  join(
    packageRoot,
    "..",
    "..",
    "..",
    "supabase",
    "migrations",
    "20260625155733_place_intelligence_cache.sql"
  ),
  "utf8"
);
const writerDigestGrantSql = readFileSync(
  join(
    packageRoot,
    "..",
    "..",
    "..",
    "supabase",
    "migrations",
    "20260701121500_confluendo_inbox_writer_digest_usage.sql"
  ),
  "utf8"
);

const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

describe("production inbox telemetry adapter (no database)", () => {
  it("does not reference Vamo product tables", () => {
    assert.doesNotMatch(telemetrySource, /location_canonicals/);
    assert.doesNotMatch(telemetrySource, /location_source_refs/);
    assert.doesNotMatch(telemetrySource, /public\.trips/);
    assert.match(telemetrySource, /confluendo_inbox\.shipments/);
  });

  it("refuses when caller-side production telemetry proof fails", async () => {
    const fake = new FakeClient();
    const result = await readPostgresProductionInboxApplyTelemetry({
      client: fake,
      packageIds: ["pkg-1"],
      proveTelemetry: () => false
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.code, "telemetry_not_proven");
    assert.ok(!fake.sql.some((sql) => /from confluendo_inbox\.shipments/i.test(sql)));
  });
});

describe(
  "postgres production inbox telemetry",
  { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for telemetry smoke." },
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
      await client.query(telemetryRoleSql);
      await client.query("grant confluendo_inbox_telemetry to postgres");
    });

    it("reads pending, applied, and failed apply telemetry as telemetry role", async () => {
      const pendingId = "production-inbox:telemetry:pending";
      const appliedId = "production-inbox:telemetry:applied";
      const failedId = "production-inbox:telemetry:failed";

      await deliverAsWriter(client, packageForTest(pendingId));
      await deliverAsWriter(client, packageForTest(appliedId));
      await deliverAsWriter(client, packageForTest(failedId));

      await applyPackage(client, appliedId);
      await client.query(
        `
          update confluendo_inbox.shipments
          set status = 'consumer_apply_failed'
          where package_id = $1
        `,
        [failedId]
      );
      await client.query(
        `
          insert into confluendo_inbox.apply_log (package_id, result, detail)
          values ($1, 'consumer_apply_failed', 'schema mismatch')
        `,
        [failedId]
      );

      await client.query("set role confluendo_inbox_telemetry");
      let result;
      try {
        result = await readPostgresProductionInboxApplyTelemetry({
          client,
          packageIds: [pendingId, appliedId, failedId],
          proveTelemetry: () => true
        });
      } finally {
        await client.query("reset role");
      }

      assert.equal(result.ok, true);
      if (!result.ok) return;
      const byId = Object.fromEntries(result.packages.map((pkg) => [pkg.packageId, pkg]));
      assert.equal(byId[pendingId]?.shipmentStatus, "production_inbox_delivered");
      assert.equal(byId[pendingId]?.pendingItemCount, 2);
      assert.equal(byId[appliedId]?.shipmentStatus, "consumer_applied");
      assert.equal(byId[failedId]?.shipmentStatus, "consumer_apply_failed");
      assert.equal(byId[failedId]?.latestApplyLogResult, "consumer_apply_failed");
    });
  }
);

class FakeClient implements PgClientLike {
  readonly sql: string[] = [];

  async query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string
  ): Promise<QueryResult<T>> {
    this.sql.push(sql.trim());
    if (sql.includes("pg_roles")) {
      return this.result<T>([{ exists: false }]);
    }
    if (sql.includes("to_regclass('confluendo_guard.environment_sentinel')")) {
      return this.result<T>([{ table_name: null }]);
    }
    return this.result<T>([]);
  }

  private result<T extends Record<string, unknown>>(rows: Record<string, unknown>[]): QueryResult<T> {
    return { rows: rows as T[], rowCount: rows.length, command: "SELECT", oid: 0, fields: [] };
  }
}

function packageForTest(packageId: string): ProductionInboxPackage {
  const report = sampleProgressiveRunSnapshot.entries[0]?.report;
  if (!report) {
    throw new Error("sample progressive report missing");
  }
  return buildProductionInboxPackage({
    packageId,
    consumerKey: "vamo",
    runReport: report,
    candidates: [candidate()],
    approvedBy: "telemetry-smoke",
    approvalReason: "telemetry smoke"
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
        canonical_id: "030d1b0a-a43e-5f7f-bb32-e4ce5a516bc5",
        provider: "fsq_os_places",
        source_place_id: "fsq_colosseum",
        source_payload_hash: "payload-hash",
        attribution: "FSQ Open Source Places",
        fetched_at: "2026-07-01T10:00:00.000Z"
      }
    }
  };
}

async function deliverAsWriter(client: Client, pkg: ProductionInboxPackage): Promise<void> {
  await client.query("set role confluendo_inbox_writer");
  try {
    const delivered = await deliverPostgresProductionInboxPackage({
      client,
      package: pkg,
      proveProduction: () => true
    });
    assert.equal(delivered.ok, true);
  } finally {
    await client.query("reset role");
  }
}

async function applyPackage(client: Client, packageId: string): Promise<void> {
  await client.query(
    `
      select confluendo_inbox.apply_confluendo_shipment(
        $1,
        'telemetry-smoke',
        'telemetry smoke apply'
      )
    `,
    [packageId]
  );
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
