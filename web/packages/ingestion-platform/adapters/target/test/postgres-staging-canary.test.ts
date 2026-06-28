import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import { Client, type QueryResult } from "pg";

import {
  applyPostgresStagingCanary,
  rollbackPostgresStagingCanary
} from "../src/postgres-staging-canary.js";
import type { PgClientLike } from "../src/postgres-dry-run.js";
import type { StagedCandidate } from "../../../core/src/index.js";
import type { TargetProjectSpec } from "../../../spec/src/index.js";

const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

// Runs in CI without a database: the staging guard must block before any
// planning or write SQL is issued.
describe("staging canary guard (no database)", () => {
  it("refuses to write when staging is not proven, issuing no write SQL", async () => {
    const fake = new FakeClient("staging");
    const result = await applyPostgresStagingCanary({
      client: fake,
      target: targetSpec(),
      candidates: [candidate("colosseum", { source_id: "colosseum", display_name: "Colosseum" })],
      proveStaging: () => false
    });

    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.code, "staging_not_proven");
    assert.ok(fake.sql.some((sql) => /^begin/i.test(sql)));
    assert.ok(fake.sql.some((sql) => /^rollback/i.test(sql)));
    assert.ok(
      !fake.sql.some((sql) => /insert\s+into|update\s+|delete\s+from/i.test(sql)),
      `no write SQL expected, saw: ${fake.sql.join(" | ")}`
    );
  });

  it("refuses when the caller proof is true but the database sentinel is absent", async () => {
    const fake = new FakeClient();
    const result = await applyPostgresStagingCanary({
      client: fake,
      target: targetSpec(),
      candidates: [candidate("colosseum", { source_id: "colosseum", display_name: "Colosseum" })],
      proveStaging: () => true
    });

    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.code, "staging_not_proven");
    assert.ok(fake.sql.some((sql) => /current_setting\('ingestion\.environment'/.test(sql)));
    assert.ok(
      !fake.sql.some((sql) => /insert\s+into|update\s+|delete\s+from/i.test(sql)),
      `no write SQL expected, saw: ${fake.sql.join(" | ")}`
    );
  });
});

describe(
  "postgres staging canary apply/rollback",
  { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for staging-canary smoke." },
  () => {
    let client: Client;

    before(async () => {
      assert.ok(databaseUrl);
      client = new Client({ connectionString: databaseUrl });
      await client.connect();
    });

    after(async () => {
      await client.query("drop schema if exists canary_target cascade");
      await client.end();
    });

    beforeEach(async () => {
      await client.query("drop schema if exists canary_target cascade");
      await client.query("select set_config('ingestion.environment', 'staging', false)");
      await client.query("create schema canary_target");
      await client.query(`
        create table canary_target.generic_places (
          source_id text primary key,
          display_name text not null,
          category text
        )
      `);
    });

    it("applies bounded inserts in one transaction and is idempotent on re-run", async () => {
      const candidates = [
        candidate("colosseum", { source_id: "colosseum", display_name: "Colosseum", category: "landmark" }),
        candidate("pantheon", { source_id: "pantheon", display_name: "Pantheon", category: "landmark" })
      ];

      const first = await applyPostgresStagingCanary({
        client,
        target: targetSpec(),
        candidates,
        proveStaging: async () => true
      });
      assert.equal(first.ok, true);
      if (!first.ok) return;
      assert.equal(first.wroteToTarget, true);
      assert.equal(first.counts.insert, 2);
      assert.equal(first.counts.writeCount, 2);
      assert.equal(await rowCount(client), 2);

      const second = await applyPostgresStagingCanary({
        client,
        target: targetSpec(),
        candidates,
        proveStaging: async () => true
      });
      assert.equal(second.ok, true);
      if (!second.ok) return;
      assert.equal(second.wroteToTarget, false);
      assert.equal(second.counts.noOp, 2);
      assert.equal(second.counts.writeCount, 0);
      assert.equal(await rowCount(client), 2);
    });

    it("captures prior state on update and reverses it on rollback", async () => {
      await client.query(
        `insert into canary_target.generic_places (source_id, display_name, category)
         values ('colosseum', 'Old Name', 'landmark')`
      );

      const applied = await applyPostgresStagingCanary({
        client,
        target: targetSpec(),
        candidates: [
          candidate("colosseum", { source_id: "colosseum", display_name: "Colosseum", category: "landmark" })
        ],
        proveStaging: async () => true
      });
      assert.equal(applied.ok, true);
      if (!applied.ok) return;
      assert.equal(applied.counts.update, 1);
      assert.equal(await displayName(client, "colosseum"), "Colosseum");
      const updateItem = applied.items.find((item) => item.operation === "update");
      assert.equal(updateItem?.priorState?.display_name, "Old Name");

      const rollback = await rollbackPostgresStagingCanary({
        client,
        items: applied.items,
        proveStaging: async () => true
      });
      assert.equal(rollback.ok, true);
      assert.equal(rollback.reverted.restoredUpdates, 1);
      assert.equal(await displayName(client, "colosseum"), "Old Name");
    });

    it("removes inserted rows on rollback and is idempotent", async () => {
      const applied = await applyPostgresStagingCanary({
        client,
        target: targetSpec(),
        candidates: [
          candidate("colosseum", { source_id: "colosseum", display_name: "Colosseum", category: "landmark" })
        ],
        proveStaging: async () => true
      });
      assert.equal(applied.ok, true);
      if (!applied.ok) return;
      assert.equal(await rowCount(client), 1);

      const rollback = await rollbackPostgresStagingCanary({
        client,
        items: applied.items,
        proveStaging: async () => true
      });
      assert.equal(rollback.reverted.deletedInserts, 1);
      assert.equal(await rowCount(client), 0);

      // Idempotent: rolling back again deletes nothing more.
      const again = await rollbackPostgresStagingCanary({
        client,
        items: applied.items,
        proveStaging: async () => true
      });
      assert.equal(again.reverted.deletedInserts, 0);
      assert.equal(await rowCount(client), 0);
    });

    it("refuses to write against a real connection when staging is not proven", async () => {
      const result = await applyPostgresStagingCanary({
        client,
        target: targetSpec(),
        candidates: [candidate("colosseum", { source_id: "colosseum", display_name: "Colosseum" })],
        proveStaging: async () => false
      });
      assert.equal(result.ok, false);
      if (result.ok) return;
      assert.equal(result.code, "staging_not_proven");
      assert.equal(await rowCount(client), 0);
    });

    it("blocks and writes nothing when the write count exceeds the bound", async () => {
      const result = await applyPostgresStagingCanary({
        client,
        target: targetSpec(),
        candidates: [
          candidate("colosseum", { source_id: "colosseum", display_name: "Colosseum" }),
          candidate("pantheon", { source_id: "pantheon", display_name: "Pantheon" })
        ],
        proveStaging: async () => true,
        maxRows: 1
      });
      assert.equal(result.ok, false);
      if (result.ok) return;
      assert.equal(result.code, "row_bound_exceeded");
      assert.equal(await rowCount(client), 0);
    });

    it("blocks and writes nothing when the diff drifts from review", async () => {
      const result = await applyPostgresStagingCanary({
        client,
        target: targetSpec(),
        candidates: [
          candidate("colosseum", { source_id: "colosseum", display_name: "Colosseum" }),
          candidate("pantheon", { source_id: "pantheon", display_name: "Pantheon" })
        ],
        proveStaging: async () => true,
        expectedWrite: { insert: 1, update: 0 }
      });
      assert.equal(result.ok, false);
      if (result.ok) return;
      assert.equal(result.code, "diff_drift");
      assert.equal(await rowCount(client), 0);
    });
  }
);

class FakeClient implements PgClientLike {
  readonly sql: string[] = [];

  constructor(private readonly env?: string) {}

  async query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string
  ): Promise<QueryResult<T>> {
    this.sql.push(sql.trim());
    if (sql.includes("current_setting('ingestion.environment'")) {
      return {
        rows: [{ env: this.env ?? null }],
        rowCount: 1,
        command: "SELECT",
        oid: 0,
        fields: []
      } as unknown as QueryResult<T>;
    }
    return { rows: [], rowCount: 0, command: "", oid: 0, fields: [] } as unknown as QueryResult<T>;
  }
}

function targetSpec(): TargetProjectSpec {
  return {
    normalizedSpecVersion: 1,
    kind: "ingestion.target",
    version: 1,
    id: "vamo-staging-canary",
    name: "Vamo Staging Canary",
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
      writeMode: "approved_write"
    },
    shipment: {
      defaultMode: "approved_write",
      tables: [
        {
          table: "canary_target.generic_places",
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
    targetProject: "vamo",
    targetProfile: "places",
    payload: {
      generic_places: payload
    }
  };
}

async function rowCount(client: Client): Promise<number> {
  const result = await client.query<{ count: string }>(
    "select count(*)::text as count from canary_target.generic_places"
  );
  return Number(result.rows[0]?.count ?? 0);
}

async function displayName(client: Client, sourceId: string): Promise<string | null> {
  const result = await client.query<{ display_name: string }>(
    "select display_name from canary_target.generic_places where source_id = $1",
    [sourceId]
  );
  return result.rows[0]?.display_name ?? null;
}
