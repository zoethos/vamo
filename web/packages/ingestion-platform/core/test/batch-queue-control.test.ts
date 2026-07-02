import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { sampleVamoEuPoiBatchYaml } from "../src/batch-plan-read-model.js";
import { sampleVamoEuPoiBatchQueueSnapshot, buildBatchQueueSnapshotFromItems } from "../src/batch-queue-read-model.js";
import { loadBatchQueueSnapshot } from "../src/batch-queue-control-read.js";
import { persistBatchQueueSnapshot } from "../src/batch-queue-control.js";
import { CONTROL_TABLES } from "../src/control-models.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

describe("batch queue control persistence", () => {
  it("returns null when batch queue tables are absent", async () => {
    const client = {
      async query<T extends Record<string, unknown>>() {
        const error = new Error("relation does not exist") as Error & { code: string };
        error.code = "42P01";
        throw error;
      }
    };
    const snapshot = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
    assert.equal(snapshot, null);
  });

  it(
    "persists, re-persists idempotently, and reloads the Vamo sample queue",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.query(controlSchemaSql);

        const tables = await client.query<{ table_name: string }>(
          `
            select table_name
            from information_schema.tables
            where table_schema = 'ingestion_platform'
            order by table_name
          `
        );
        assert.equal(CONTROL_TABLES.length, 20);
        assert.deepEqual(
          tables.rows.map((row) => row.table_name),
          [...CONTROL_TABLES].sort()
        );

        await client.query(
          `
            insert into ingestion_platform.ingestion_projects (project_key, display_name)
            values ('vamo', 'Vamo')
          `
        );

        const parsed = parseBatchPlanSpec(sampleVamoEuPoiBatchYaml());
        assert.equal(parsed.ok, true);
        if (!parsed.ok) {
          throw new Error("sample yaml failed to parse");
        }

        const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
        const firstPersist = await persistBatchQueueSnapshot({
          client,
          projectKey: "vamo",
          snapshot,
          spec: parsed.spec,
          now: "2026-07-02T12:00:00.000Z"
        });
        assert.equal(firstPersist.ok, true);

        const planCount = await client.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_batch_plans`
        );
        const itemCount = await client.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_batch_queue_items`
        );
        assert.equal(planCount.rows[0]?.count, "1");
        assert.equal(itemCount.rows[0]?.count, "36");

        const updatedSnapshot = buildBatchQueueSnapshotFromItems({
          planId: snapshot.planId,
          projectKey: snapshot.projectKey,
          targetKey: snapshot.targetKey,
          targetEnvironment: snapshot.targetEnvironment,
          sourceKey: snapshot.sourceKey,
          safetyMode: snapshot.safetyMode,
          items: snapshot.items.map((item, index) =>
            index === 0 ? { ...item, status: "dry_run_ready" } : item
          )
        });
        await persistBatchQueueSnapshot({
          client,
          projectKey: "vamo",
          snapshot: updatedSnapshot,
          spec: parsed.spec,
          now: "2026-07-02T12:05:00.000Z"
        });

        const planCountAfter = await client.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_batch_plans`
        );
        const itemCountAfter = await client.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_batch_queue_items`
        );
        assert.equal(planCountAfter.rows[0]?.count, "1");
        assert.equal(itemCountAfter.rows[0]?.count, "36");

        const firstItem = await client.query<{ status: string }>(
          `
            select status
            from ingestion_platform.ingestion_batch_queue_items
            order by run_order asc
            limit 1
          `
        );
        assert.equal(firstItem.rows[0]?.status, "dry_run_ready");

        const loaded = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
        assert.ok(loaded);
        assert.equal(loaded.progress.total, 36);
        assert.equal(loaded.targetKey, "vamo-place-intelligence");
        assert.equal(loaded.targetEnvironment, "staging");
        assert.equal(loaded.coverage.perCountry.italy, 12);
        assert.equal(loaded.coverage.perCountry.france, 8);
        assert.equal(loaded.coverage.perCountry.germany, 8);
        assert.equal(loaded.coverage.perCountry.spain, 8);
        assert.equal(loaded.coverage.perCategory.poi, 9);
        assert.equal(loaded.coverage.matrix.italy?.poi, 3);
        assert.equal(loaded.items[0]?.status, "dry_run_ready");
      } finally {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.end();
      }
    }
  );
});
