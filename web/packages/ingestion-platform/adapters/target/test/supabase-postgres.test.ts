import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import { Client } from "pg";

import type { StagedCandidate } from "../../../core/src/index.js";
import type { TargetProjectSpec } from "../../../spec/src/index.js";
import { planSupabasePostgresDryRun } from "../src/supabase-postgres.js";
import {
  evaluateSupabaseTargetSpecSecurity,
  inspectSupabaseTargetSecurity
} from "../src/supabase-security-checks.js";

import {
  resetDisposableTestDatabase,
  resolveDisposableTestDatabaseUrl
} from "../../../core/test/disposable-test-database.js";

const databaseUrl = resolveDisposableTestDatabaseUrl(process.env.INGESTION_TEST_DATABASE_URL);

describe("supabase target spec security", () => {
  it("blocks unsafe service-role and approved-write posture before any database connection", () => {
    const findings = evaluateSupabaseTargetSpecSecurity(
      targetSpec({
        exposeServiceRoleToBrowser: true,
        serverSideOnly: false,
        forbidBrowserServiceRole: false,
        writeMode: "approved_write"
      })
    );

    assert.deepEqual(
      findings.map((finding) => finding.code),
      [
        "service_role_browser_exposure",
        "target_not_server_side",
        "browser_service_role_not_forbidden",
        "production_writes_disabled"
      ]
    );
  });
});

describe(
  "supabase/postgres dry-run target adapter",
  { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for Supabase/Postgres target smoke." },
  () => {
    let client: Client;

    before(async () => {
      assert.ok(databaseUrl);
      client = new Client({ connectionString: databaseUrl });
      await client.connect();
      await client.query(`
        do $$
        begin
          if not exists (select 1 from pg_roles where rolname = 'anon') then
            create role anon nologin;
          end if;
        end
        $$;
      `);
    });

    after(async () => {
      await resetDisposableTestDatabase(client, databaseUrl!, { schemas: ["supabase_target"] });
      await client.end();
    });

    beforeEach(async () => {
      await resetDisposableTestDatabase(client, databaseUrl!, { schemas: ["supabase_target"] });
      await client.query("create schema supabase_target");
      await client.query(`
        create table supabase_target.generic_places (
          source_id text primary key,
          display_name text not null,
          category text
        )
      `);
    });

    it("blocks exposed schema tables without RLS", async () => {
      const findings = await inspectSupabaseTargetSecurity({
        client,
        target: targetSpec()
      });

      assert.equal(
        findings.some((finding) => finding.code === "exposed_table_without_rls"),
        true
      );
    });

    it("blocks missing explicit Data API table grants when required", async () => {
      await client.query("alter table supabase_target.generic_places enable row level security");

      const findings = await inspectSupabaseTargetSecurity({
        client,
        target: targetSpec({ requireExplicitDataApiGrants: true })
      });

      assert.equal(
        findings.some((finding) => finding.code === "missing_explicit_data_api_grant"),
        true
      );
    });

    it("produces a dry-run shipment plan for a guarded Supabase/Postgres target", async () => {
      await client.query("alter table supabase_target.generic_places enable row level security");
      await client.query("grant select on supabase_target.generic_places to anon");

      const result = await planSupabasePostgresDryRun({
        client,
        target: targetSpec({ requireExplicitDataApiGrants: true }),
        candidates: [
          candidate("colosseum", {
            source_id: "colosseum",
            display_name: "Colosseum",
            category: "landmark"
          })
        ]
      });

      assert.equal(result.compatible, true);
      assert.deepEqual(result.securityFindings, []);
      assert.deepEqual(result.shipmentPlan.items.map((item) => item.operation), ["insert"]);
      assert.equal(await rowCount(client), 0);
    });
  }
);

interface TargetOverrides {
  exposeServiceRoleToBrowser?: boolean;
  serverSideOnly?: boolean;
  forbidBrowserServiceRole?: boolean;
  writeMode?: "dry_run" | "approved_write";
  requireExplicitDataApiGrants?: boolean;
}

function targetSpec(overrides: TargetOverrides = {}): TargetProjectSpec {
  const writeMode = overrides.writeMode ?? "dry_run";

  return {
    normalizedSpecVersion: 1,
    kind: "ingestion.target",
    version: 1,
    id: "supabase-target",
    name: "Supabase Target",
    adapter: "supabase_postgres",
    engine: {
      type: "supabase_postgres",
      dsnEnv: "INGESTION_TEST_DATABASE_URL",
      serviceRoleSecretEnv: "SUPABASE_SERVICE_ROLE",
      exposeServiceRoleToBrowser: overrides.exposeServiceRoleToBrowser ?? false
    },
    security: {
      serverSideOnly: overrides.serverSideOnly ?? true,
      forbidBrowserServiceRole: overrides.forbidBrowserServiceRole ?? true,
      requireRlsOnExposedSchemas: true,
      exposedSchemas: ["supabase_target"],
      requireExplicitDataApiGrants: overrides.requireExplicitDataApiGrants ?? false,
      dataApiRoles: overrides.requireExplicitDataApiGrants ? ["anon"] : [],
      dataApiPrivileges: overrides.requireExplicitDataApiGrants ? ["select"] : [],
      writeMode
    },
    shipment: {
      defaultMode: writeMode,
      tables: [
        {
          table: "supabase_target.generic_places",
          mode: "upsert",
          upsertKeys: ["source_id"]
        }
      ]
    }
  };
}

function candidate(recordKey: string, payload: Record<string, unknown>): StagedCandidate {
  return {
    recordKey,
    sourceLineNumber: 1,
    sourceCursor: 1,
    targetProject: "test",
    targetProfile: "places",
    payload: {
      generic_places: payload
    }
  };
}

async function rowCount(client: Client): Promise<number> {
  const result = await client.query<{ count: string }>(
    "select count(*)::text as count from supabase_target.generic_places"
  );
  return Number(result.rows[0]?.count ?? 0);
}
