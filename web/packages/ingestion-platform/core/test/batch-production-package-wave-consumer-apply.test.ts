import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import { Client } from "pg";

import { deliverPostgresProductionInboxPackage } from "../../adapters/target/src/postgres-production-inbox.js";
import type { ProductionInboxPackage } from "../src/shipment-package.js";
import { buildProductionInboxPackage } from "../src/shipment-package.js";
import type { StagedCandidate } from "../src/pipeline-runner.js";
import { executeProductionPackageConsumerApply } from "../src/batch-production-package-wave-consumer-apply.js";
import { sampleProgressiveRunSnapshot } from "../src/progressive-read-model.js";
import type { AdminPrincipal } from "../src/admin-auth.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
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
const applyRoleSql = readFileSync(
  "../../../supabase/migrations/20260708120000_confluendo_inbox_apply_executor.sql",
  "utf8"
);

import {
  resetDisposableTestDatabase,
  resolveDisposableTestDatabaseUrl
} from "./disposable-test-database.js";

const databaseUrl = resolveDisposableTestDatabaseUrl(process.env.INGESTION_TEST_DATABASE_URL);
const PACKAGE_ID = "production-inbox:consumer-apply:orchestration";
const WAVE_KEY = "batch-production-inbox:vamo-eu-poi-sample:wave:101:unit:vamo-place-intelligence:paris-france:landmark";
const UNIT_KEY = "vamo-place-intelligence:paris-france:landmark";
const NOW = "2026-07-08T21:40:00.000Z";

describe(
  "executeProductionPackageConsumerApply",
  { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for consumer apply DB smoke." },
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
      await setupControlPlane(client);
      await setupProductionInbox(client);
      await deliverAsWriter(client, packageForTest(PACKAGE_ID));
    });

    it("applies via the dedicated inbox role and records a control audit row", async () => {
      assert.ok(databaseUrl);
      const result = await executeProductionPackageConsumerApply({
        projectKey: "vamo",
        packageId: PACKAGE_ID,
        auditReason: "Apply consumer package smoke.",
        principal: adminPrincipal(),
        actor: { type: "operator", id: "admin-smoke" },
        controlConnectionString: databaseUrl,
        applyConnectionString: applyRoleDatabaseUrl(databaseUrl),
        proveApply: () => true,
        now: NOW
      });

      assert.equal(result.ok, true);
      if (!result.ok) return;
      assert.equal(result.applyResult.status, "consumer_applied");
      assert.equal(result.applyResult.applied, 2);
      assert.ok(result.auditId);
      assert.equal(result.idempotentReplay, false);

      const audit = await client.query<{
        actorType: string;
        actorId: string | null;
        action: string;
        targetType: string;
        reason: string | null;
        packageId: string;
      }>(
        `
          select
            actor_type as "actorType",
            actor_id as "actorId",
            action,
            target_type as "targetType",
            reason,
            payload->>'packageId' as "packageId"
          from ingestion_platform.ingestion_audit_log
          where id = $1::bigint
        `,
        [result.auditId]
      );

      assert.equal(audit.rows[0]?.actorType, "operator");
      assert.equal(audit.rows[0]?.actorId, "admin-smoke");
      assert.equal(audit.rows[0]?.action, "apply_batch_production_package_wave");
      assert.equal(audit.rows[0]?.targetType, "batch_production_package_wave");
      assert.equal(audit.rows[0]?.reason, "Apply consumer package smoke.");
      assert.equal(audit.rows[0]?.packageId, PACKAGE_ID);

      const product = await client.query<{ count: string }>(
        `select count(*)::text as count from public.location_canonicals where source_place_id = 'fsq_colosseum'`
      );
      assert.equal(product.rows[0]?.count, "1");
    });
  }
);

async function setupControlPlane(client: Client): Promise<void> {
  await client.query(controlSchemaSql);
  const project = await client.query<{ id: string }>(
    `
      insert into ingestion_platform.ingestion_projects (project_key, display_name)
      values ('vamo', 'Vamo')
      returning id::text as id
    `
  );
  const plan = await client.query<{ id: string }>(
    `
      insert into ingestion_platform.ingestion_batch_plans (
        project_id, plan_key, source_key, target_key, target_environment, safety_mode, spec, plan_summary, status
      ) values (
        $1::bigint, 'vamo-eu-poi-sample', 'fsq-os-places-sample', 'vamo-place-intelligence',
        'staging', 'dry_run', '{}'::jsonb, '{}'::jsonb, 'active'
      )
      returning id::text as id
    `,
    [project.rows[0]!.id]
  );
  const queue = await client.query<{ id: string }>(
    `
      insert into ingestion_platform.ingestion_batch_queue_items (
        batch_plan_id, unit_key, country_code, geography_key, geography_label, geography_kind,
        category, source_key, target_key, target_environment, status, priority, run_order, run_report
      ) values (
        $1::bigint, $2, 'FR', 'paris-france', 'Paris, France', 'city',
        'landmark', 'fsq-os-places-sample', 'vamo-place-intelligence', 'staging',
        'production_package_delivered', 0, 1,
        '{"wroteToTarget":false,"rowsProcessed":2,"insertCount":2,"updateCount":0,"noOpCount":0}'::jsonb
      )
      returning id::text as id
    `,
    [plan.rows[0]!.id, UNIT_KEY]
  );
  const wave = await client.query<{ id: string }>(
    `
      insert into ingestion_platform.ingestion_batch_production_package_waves (
        project_id, batch_plan_id, wave_key, target_key, target_environment, schema_contract,
        max_units, max_rows, max_packages, approval_audit_id, approval_reason, approved_by,
        approved_at, approval_expires_at, actor_type, actor_id, status, package_id, package_key,
        delivery_audit_id, delivery_status
      ) values (
        $1::bigint, $2::bigint, $3, 'vamo-place-intelligence', 'production', 'vamo-place-intelligence@1',
        1, 2, 1, '101', 'approve smoke', '{"email":"admin@vamo.test"}'::jsonb,
        $4::timestamptz, $4::timestamptz + interval '15 minutes', 'operator', 'admin-smoke',
        'delivered', $5, $5, '102', 'production_package_delivered'
      )
      returning id::text as id
    `,
    [project.rows[0]!.id, plan.rows[0]!.id, WAVE_KEY, NOW, PACKAGE_ID]
  );
  await client.query(
    `
      insert into ingestion_platform.ingestion_batch_production_package_wave_items (
        wave_id, queue_item_id, unit_key, run_order, planned_row_count, schema_contract,
        package_key, package_id, status, checksum
      ) values (
        $1::bigint, $2::bigint, $3, 1, 2, 'vamo-place-intelligence@1',
        $4, $4, 'delivered', 'checksum-smoke'
      )
    `,
    [wave.rows[0]!.id, queue.rows[0]!.id, UNIT_KEY, PACKAGE_ID]
  );
}

async function setupProductionInbox(client: Client): Promise<void> {
  await createSupabaseRoles(client);
  await client.query("create role confluendo_inbox_apply_app login password 'test' inherit");
  await createSupabaseAuthStub(client);
  await createVamoSchemaStub(client);
  await client.query("create schema if not exists extensions");
  await client.query("create extension if not exists pgcrypto with schema extensions");
  await client.query(placeIntelligenceSql);
  await client.query(confluendoInboxSql);
  await client.query(writerDigestGrantSql);
  await client.query(applyRoleSql);
  await client.query("grant confluendo_inbox_apply to confluendo_inbox_apply_app");
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
    approvedBy: "delivery-smoke",
    approvalReason: "delivery smoke"
  });
}

function candidate(): StagedCandidate {
  return {
    recordKey: "fsq_colosseum",
    sourceLineNumber: 1,
    sourceCursor: 1,
    targetProject: "vamo",
    targetProfile: "place-intelligence",
    sourceScope: { geography: "paris-france", category: "landmark" },
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

function adminPrincipal(): AdminPrincipal {
  return {
    provider: "supabase",
    userId: "admin-smoke",
    email: "admin@vamo.test",
    role: "admin",
    scopes: ["vamo"],
    assuranceLevel: "aal2",
    mfaRequired: true,
    hasVerifiedMfaFactor: true,
    stepUpSatisfiedAt: "2026-07-08T21:35:00.000Z"
  };
}

function applyRoleDatabaseUrl(url: string): string {
  return url.replace(/\/\/[^@]+@/, "//confluendo_inbox_apply_app:test@");
}

async function cleanup(client: Client): Promise<void> {
  await client.query("reset role");
  await resetDisposableTestDatabase(client, databaseUrl!, { schemas: ["ingestion_platform"] });
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
  await resetDisposableTestDatabase(client, databaseUrl!, {
    roleRevocations: [
      { grantedRole: "confluendo_inbox_apply", memberRole: "confluendo_inbox_apply_app" }
    ],
    ownedRoles: ["confluendo_inbox_apply_app"],
    roles: ["confluendo_inbox_apply_app"]
  });
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
