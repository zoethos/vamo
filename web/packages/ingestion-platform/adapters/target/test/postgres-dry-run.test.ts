import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import { Client } from "pg";

import { planPostgresDryRun } from "../src/postgres-dry-run.js";
import type { StagedCandidate } from "../../../core/src/index.js";
import type { TargetProjectSpec } from "../../../spec/src/index.js";

const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

describe(
  "postgres dry-run target adapter",
  { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for Postgres dry-run smoke." },
  () => {
    let client: Client;

    before(async () => {
      assert.ok(databaseUrl);
      client = new Client({ connectionString: databaseUrl });
      await client.connect();
    });

    after(async () => {
      await client.query("drop schema if exists dry_run_target cascade");
      await client.end();
    });

    beforeEach(async () => {
      await client.query("drop schema if exists dry_run_target cascade");
      await client.query("create schema dry_run_target");
      await client.query(`
        create table dry_run_target.generic_places (
          source_id text primary key,
          display_name text not null,
          category text
        )
      `);
    });

    it("produces insert diff against an empty target without writing", async () => {
      const plan = await planPostgresDryRun({
        client,
        target: targetSpec(),
        candidates: [
          candidate("colosseum", {
            source_id: "colosseum",
            display_name: "Colosseum",
            category: "landmark"
          })
        ]
      });
      const count = await rowCount(client);

      assert.equal(plan.compatible, true);
      assert.deepEqual(plan.items.map((item) => item.operation), ["insert"]);
      assert.equal(plan.items[0]?.targetTable, "dry_run_target.generic_places");
      assert.equal(count, 0);
    });

    it("detects existing row no-op", async () => {
      await client.query(
        `
          insert into dry_run_target.generic_places (source_id, display_name, category)
          values ('colosseum', 'Colosseum', 'landmark')
        `
      );

      const plan = await planPostgresDryRun({
        client,
        target: targetSpec(),
        candidates: [
          candidate("colosseum", {
            source_id: "colosseum",
            display_name: "Colosseum",
            category: "landmark"
          })
        ]
      });

      assert.equal(plan.compatible, true);
      assert.deepEqual(plan.items.map((item) => item.operation), ["no_op"]);
      assert.equal(await rowCount(client), 1);
    });

    it("detects existing row update", async () => {
      await client.query(
        `
          insert into dry_run_target.generic_places (source_id, display_name, category)
          values ('colosseum', 'Old Name', 'landmark')
        `
      );

      const plan = await planPostgresDryRun({
        client,
        target: targetSpec(),
        candidates: [
          candidate("colosseum", {
            source_id: "colosseum",
            display_name: "Colosseum",
            category: "landmark"
          })
        ]
      });

      assert.equal(plan.compatible, true);
      assert.deepEqual(plan.items.map((item) => item.operation), ["update"]);
      assert.notEqual(plan.items[0]?.checksum, plan.items[0]?.previousChecksum);
      assert.equal(await rowCount(client), 1);
    });

    it("reports missing target table before any write", async () => {
      const plan = await planPostgresDryRun({
        client,
        target: targetSpec("dry_run_target.missing_places"),
        candidates: [
          candidate("colosseum", {
            source_id: "colosseum",
            display_name: "Colosseum"
          })
        ]
      });

      assert.equal(plan.compatible, false);
      assert.equal(plan.items.length, 0);
      assert.equal(plan.incompatibilities[0]?.code, "missing_table");
      assert.equal(await rowCount(client), 0);
    });

    it("reports missing upsert key before any write", async () => {
      const plan = await planPostgresDryRun({
        client,
        target: targetSpec(),
        candidates: [
          candidate("colosseum", {
            display_name: "Colosseum",
            category: "landmark"
          })
        ]
      });

      assert.equal(plan.compatible, false);
      assert.equal(plan.items.length, 0);
      assert.equal(plan.incompatibilities[0]?.code, "missing_upsert_key");
      assert.equal(await rowCount(client), 0);
    });
  }
);

function targetSpec(table = "dry_run_target.generic_places"): TargetProjectSpec {
  return {
    normalizedSpecVersion: 1,
    kind: "ingestion.target",
    version: 1,
    id: "dry-run-target",
    name: "Dry Run Target",
    adapter: "postgres",
    engine: {
      type: "postgres",
      dsnEnv: "INGESTION_TEST_DATABASE_URL",
      exposeServiceRoleToBrowser: false
    },
    security: {
      serverSideOnly: true,
      forbidBrowserServiceRole: true,
      requireRlsOnExposedSchemas: false,
      exposedSchemas: [],
      requireExplicitDataApiGrants: false,
      dataApiRoles: [],
      dataApiPrivileges: [],
      writeMode: "dry_run"
    },
    shipment: {
      defaultMode: "dry_run",
      tables: [
        {
          table,
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
    "select count(*)::text as count from dry_run_target.generic_places"
  );
  return Number(result.rows[0]?.count ?? 0);
}
