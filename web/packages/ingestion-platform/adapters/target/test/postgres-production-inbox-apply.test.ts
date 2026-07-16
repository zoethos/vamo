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
import {
  applyPostgresProductionInboxPackage,
  readPostgresProductionInboxApplyPreflight
} from "../src/postgres-production-inbox-apply.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..", "..");
const applySource = readFileSync(join(testDir, "..", "src", "postgres-production-inbox-apply.js"), "utf8");
const confluendoInboxSql = readFileSync(
  join(packageRoot, "..", "..", "..", "supabase", "migrations", "20260701100233_confluendo_inbox.sql"),
  "utf8"
);
const applyRoleSql = readFileSync(
  join(
    packageRoot,
    "..",
    "..",
    "..",
    "supabase",
    "migrations",
    "20260708120000_confluendo_inbox_apply_executor.sql"
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

import {
  resetDisposableTestDatabase,
  resolveDisposableTestDatabaseUrl
} from "../../../core/test/disposable-test-database.js";

const databaseUrl = resolveDisposableTestDatabaseUrl(process.env.INGESTION_TEST_DATABASE_URL);

describe("production inbox apply adapter (no database)", () => {
  it("does not reference Vamo product tables directly", () => {
    assert.doesNotMatch(applySource, /insert into public\.location_canonicals/i);
    assert.doesNotMatch(applySource, /insert into public\.location_source_refs/i);
    assert.doesNotMatch(applySource, /update public\.location_canonicals/i);
    assert.match(applySource, /apply_confluendo_shipment/);
  });

  it("refuses when caller-side production apply proof fails", async () => {
    const fake = new FakeClient();
    const result = await readPostgresProductionInboxApplyPreflight({
      client: fake,
      packageId: "pkg-1",
      proveApply: () => false
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.code, "apply_not_proven");
    assert.ok(!fake.sql.some((sql) => /from confluendo_inbox\.shipments/i.test(sql)));
  });
});

describe(
  "postgres production inbox apply",
  { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for apply smoke." },
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
      await client.query(applyRoleSql);
      await client.query("grant confluendo_inbox_apply to postgres");
    });

    it("applies a pending delivered package", async () => {
      const packageId = "production-inbox:apply:pending";
      await deliverAsWriter(client, packageForTest(packageId));

      const preflight = await readAsApplyRole(client, packageId);
      assert.equal(preflight.ok, true);
      if (!preflight.ok) return;
      assert.equal(preflight.preflight.shipmentStatus, "production_inbox_delivered");
      assert.equal(preflight.preflight.pendingItemCount, 2);
      assert.deepEqual(preflight.preflight.targetTables, [
        "location_canonicals",
        "location_source_refs"
      ]);

      const applied = await applyAsApplyRole(client, packageId, "apply-smoke", "apply smoke");
      assert.equal(applied.ok, true);
      if (!applied.ok) return;
      assert.equal(applied.result.status, "consumer_applied");
      assert.equal(applied.result.applied, 2);
      assert.equal(applied.result.rejected, 0);
    });

    it("keeps the apply role scoped to inbox reads and the apply function", async () => {
      const privileges = await client.query<{
        canReadShipments: boolean;
        canReadItems: boolean;
        canReadApplyLog: boolean;
        canExecuteApply: boolean;
        canInsertCanonicals: boolean;
        canUpdateCanonicals: boolean;
        canInsertRefs: boolean;
        canUpdateRefs: boolean;
      }>(
        `
          select
            has_table_privilege('confluendo_inbox_apply', 'confluendo_inbox.shipments', 'SELECT') as "canReadShipments",
            has_table_privilege('confluendo_inbox_apply', 'confluendo_inbox.shipment_items', 'SELECT') as "canReadItems",
            has_table_privilege('confluendo_inbox_apply', 'confluendo_inbox.apply_log', 'SELECT') as "canReadApplyLog",
            has_function_privilege(
              'confluendo_inbox_apply',
              'confluendo_inbox.apply_confluendo_shipment(text,text,text)',
              'EXECUTE'
            ) as "canExecuteApply",
            has_table_privilege('confluendo_inbox_apply', 'public.location_canonicals', 'INSERT') as "canInsertCanonicals",
            has_table_privilege('confluendo_inbox_apply', 'public.location_canonicals', 'UPDATE') as "canUpdateCanonicals",
            has_table_privilege('confluendo_inbox_apply', 'public.location_source_refs', 'INSERT') as "canInsertRefs",
            has_table_privilege('confluendo_inbox_apply', 'public.location_source_refs', 'UPDATE') as "canUpdateRefs"
        `
      );

      assert.equal(privileges.rows[0]?.canReadShipments, true);
      assert.equal(privileges.rows[0]?.canReadItems, true);
      assert.equal(privileges.rows[0]?.canReadApplyLog, true);
      assert.equal(privileges.rows[0]?.canExecuteApply, true);
      assert.equal(privileges.rows[0]?.canInsertCanonicals, false);
      assert.equal(privileges.rows[0]?.canUpdateCanonicals, false);
      assert.equal(privileges.rows[0]?.canInsertRefs, false);
      assert.equal(privileges.rows[0]?.canUpdateRefs, false);
    });

    it("treats already-applied packages as idempotent skipped", async () => {
      const packageId = "production-inbox:apply:replay";
      await deliverAsWriter(client, packageForTest(packageId));
      const first = await applyAsApplyRole(client, packageId, "apply-smoke", "first apply");
      assert.equal(first.ok, true);

      const second = await applyAsApplyRole(client, packageId, "apply-smoke", "second apply");
      assert.equal(second.ok, true);
      if (!second.ok) return;
      assert.equal(second.result.skipped, 1);
      assert.equal(second.result.applied, 0);
    });

    it("fails closed when approved_by is missing", async () => {
      const packageId = "production-inbox:apply:missing-approved-by";
      await deliverAsWriter(client, packageForTest(packageId));

      const result = await applyAsApplyRole(client, packageId, "", "reason required");
      assert.equal(result.ok, false);
      if (result.ok) return;
      assert.equal(result.result?.error, "approved_by_required");

      const preflight = await readAsApplyRole(client, packageId);
      assert.equal(preflight.ok, true);
      if (!preflight.ok) return;
      assert.equal(preflight.preflight.latestApplyLogResult, "rejected");
      assert.match(preflight.preflight.latestApplyLogDetail ?? "", /approved_by/i);
    });

    it("fails closed when approval_reason is missing", async () => {
      const packageId = "production-inbox:apply:missing-reason";
      await deliverAsWriter(client, packageForTest(packageId));

      const result = await applyAsApplyRole(client, packageId, "apply-smoke", "");
      assert.equal(result.ok, false);
      if (result.ok) return;
      assert.equal(result.result?.error, "approval_reason_required");
    });

    it("rejects unsupported shipment status", async () => {
      const packageId = "production-inbox:apply:unsupported-status";
      await deliverAsWriter(client, packageForTest(packageId));
      await client.query(
        `
          update confluendo_inbox.shipments
          set status = 'consumer_apply_failed'
          where package_id = $1
        `,
        [packageId]
      );

      const result = await applyAsApplyRole(client, packageId, "apply-smoke", "should fail");
      assert.equal(result.ok, false);
      if (result.ok) return;
      assert.equal(result.result?.error, "invalid_shipment_status");
    });

    it("surfaces apply_log evidence on apply failure", async () => {
      const packageId = "production-inbox:apply:checksum-failure";
      const pkg = packageForTest(packageId);
      await deliverAsWriter(client, pkg);
      await client.query(
        `
          update confluendo_inbox.shipment_items
          set payload_checksum = 'deadbeef'
          where package_id = $1
        `,
        [packageId]
      );

      const result = await applyAsApplyRole(client, packageId, "apply-smoke", "checksum failure");
      assert.equal(result.ok, false);
      if (result.ok) return;
      assert.equal(result.result?.error, "payload_checksum_mismatch");

      const preflight = await readAsApplyRole(client, packageId);
      assert.equal(preflight.ok, true);
      if (!preflight.ok) return;
      assert.equal(preflight.preflight.latestApplyLogResult, "rejected");
      assert.ok(preflight.preflight.items.some((item) => item.applyError === "payload_checksum_mismatch"));
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
    approvedBy: "apply-smoke",
    approvalReason: "apply smoke"
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

async function readAsApplyRole(client: Client, packageId: string) {
  await client.query("set role confluendo_inbox_apply");
  try {
    return await readPostgresProductionInboxApplyPreflight({
      client,
      packageId,
      proveApply: () => true
    });
  } finally {
    await client.query("reset role");
  }
}

async function applyAsApplyRole(
  client: Client,
  packageId: string,
  approvedBy: string,
  approvalReason: string
) {
  await client.query("set role confluendo_inbox_apply");
  try {
    return await applyPostgresProductionInboxPackage({
      client,
      packageId,
      approvedBy,
      approvalReason,
      proveApply: () => true
    });
  } finally {
    await client.query("reset role");
  }
}

async function cleanup(client: Client): Promise<void> {
  await client.query("reset role");
  await resetDisposableTestDatabase(client, databaseUrl!, { schemas: ["confluendo_guard"] });
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
