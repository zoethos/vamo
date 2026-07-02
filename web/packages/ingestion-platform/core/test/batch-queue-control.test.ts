import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { sampleVamoEuPoiBatchYaml } from "../src/batch-plan-read-model.js";
import { sampleVamoEuPoiBatchQueueSnapshot, buildBatchQueueSnapshotFromItems } from "../src/batch-queue-read-model.js";
import { loadBatchQueueSnapshot } from "../src/batch-queue-control-read.js";
import { persistBatchQueueSnapshot } from "../src/batch-queue-control.js";
import { scheduleBatchDryRun } from "../src/batch-queue-mutations.js";
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
        assert.equal(CONTROL_TABLES.length, 23);
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

  it(
    "schedules ready queue items for dry-run idempotently and records an audit row",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.query(controlSchemaSql);
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
        await persistBatchQueueSnapshot({
          client,
          projectKey: "vamo",
          snapshot,
          spec: parsed.spec,
          now: "2026-07-02T12:00:00.000Z"
        });

        const scheduled = await scheduleBatchDryRun({
          client,
          projectKey: "vamo",
          planId: snapshot.planId,
          targetKey: snapshot.targetKey,
          actor: { type: "operator", id: "supabase:user-1" },
          reason: "schedule the EU POI dry-run batch",
          payload: { plan: { itemCount: 36 } },
          now: "2026-07-02T12:10:00.000Z"
        });
        assert.equal(scheduled.ok, true);
        assert.equal(scheduled.scheduledCount, 36);
        assert.equal(scheduled.alreadyScheduledCount, 36);
        assert.equal(scheduled.unitKeys.length, 36);
        assert.ok(scheduled.auditId);

        const statusCounts = await client.query<{ status: string; count: string }>(
          `
            select status, count(*)::text as count
            from ingestion_platform.ingestion_batch_queue_items
            group by status
            order by status
          `
        );
        assert.deepEqual(statusCounts.rows, [{ status: "dry_run_ready", count: "36" }]);

        const audit = await client.query<{
          action: string;
          reason: string;
          target_type: string;
          scheduled_count: number;
        }>(
          `
            select action,
                   reason,
                   target_type,
                   (payload->>'scheduledCount')::int as scheduled_count
            from ingestion_platform.ingestion_audit_log
            order by id desc
            limit 1
          `
        );
        assert.equal(audit.rows[0]?.action, "schedule_batch_dry_run");
        assert.equal(audit.rows[0]?.reason, "schedule the EU POI dry-run batch");
        assert.equal(audit.rows[0]?.target_type, "batch_plan");
        assert.equal(audit.rows[0]?.scheduled_count, 36);

        const replay = await scheduleBatchDryRun({
          client,
          projectKey: "vamo",
          planId: snapshot.planId,
          targetKey: snapshot.targetKey,
          actor: { type: "operator", id: "supabase:user-1" },
          reason: "repeat after refresh",
          payload: { plan: { itemCount: 36 } },
          now: "2026-07-02T12:11:00.000Z"
        });
        assert.equal(replay.scheduledCount, 0);
        assert.equal(replay.alreadyScheduledCount, 36);

        const loaded = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
        assert.ok(loaded);
        assert.equal(loaded.items.every((item) => item.status === "dry_run_ready"), true);
        assert.equal(loaded.nextAction, "36 unit(s) scheduled for dry-run execution.");
      } finally {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.end();
      }
    }
  );
});
