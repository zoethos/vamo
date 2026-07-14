import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client, type QueryResult } from "pg";

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
  it("does not commit a transaction owned by its caller", async () => {
    const parsed = parseBatchPlanSpec(sampleVamoEuPoiBatchYaml());
    assert.equal(parsed.ok, true);
    if (!parsed.ok) {
      throw new Error("sample yaml failed to parse");
    }

    const statements: string[] = [];
    const client = {
      async query<T extends Record<string, unknown>>(sql: string): Promise<QueryResult<T>> {
        statements.push(sql);
        if (sql.includes("from ingestion_platform.ingestion_projects")) {
          return { rows: [{ id: "1" }] } as unknown as QueryResult<T>;
        }
        if (sql.includes("insert into ingestion_platform.ingestion_batch_plans")) {
          return { rows: [{ id: "2" }] } as unknown as QueryResult<T>;
        }
        return { rows: [] } as unknown as QueryResult<T>;
      }
    };

    await persistBatchQueueSnapshot({
      client,
      projectKey: "vamo",
      snapshot: sampleVamoEuPoiBatchQueueSnapshot(),
      spec: parsed.spec,
      manageTransaction: false
    });

    assert.equal(statements.some((sql) => /^\s*(begin|commit|rollback)\s*$/i.test(sql)), false);
  });

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
        assert.equal(CONTROL_TABLES.length, 29);
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

  it(
    "loads an explicit batch plan when planKey is provided",
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

        const sampleSnapshot = sampleVamoEuPoiBatchQueueSnapshot();
        await persistBatchQueueSnapshot({
          client,
          projectKey: "vamo",
          snapshot: sampleSnapshot,
          spec: parsed.spec,
          now: "2026-07-02T12:00:00.000Z"
        });

        const altSnapshot = buildBatchQueueSnapshotFromItems({
          planId: "vamo-eu-full-data-v1",
          projectKey: sampleSnapshot.projectKey,
          targetKey: sampleSnapshot.targetKey,
          targetEnvironment: sampleSnapshot.targetEnvironment,
          sourceKey: sampleSnapshot.sourceKey,
          safetyMode: sampleSnapshot.safetyMode,
          items: sampleSnapshot.items.slice(0, 2).map((item) => ({
            ...item,
            status: "ready_for_dry_run",
            blockReasons: []
          })),
          planNextAction: "Alt plan queue."
        });
        const altSpec = { ...parsed.spec, id: "vamo-eu-full-data-v1" };
        await persistBatchQueueSnapshot({
          client,
          projectKey: "vamo",
          snapshot: altSnapshot,
          spec: altSpec,
          now: "2026-07-02T13:00:00.000Z"
        });

        const sampleItem = await client.query<{ id: string; unit_key: string; run_order: number }>(
          `
            select qi.id::text as id, qi.unit_key, qi.run_order
            from ingestion_platform.ingestion_batch_queue_items qi
            join ingestion_platform.ingestion_batch_plans bp on bp.id = qi.batch_plan_id
            where bp.plan_key = 'vamo-eu-poi-sample'
            order by qi.run_order asc
            limit 1
          `
        );
        const samplePlan = await client.query<{ id: string }>(
          `
            select id::text as id
            from ingestion_platform.ingestion_batch_plans
            where plan_key = 'vamo-eu-poi-sample'
          `
        );
        const insertedWave = await client.query<{ id: string }>(
          `
            insert into ingestion_platform.ingestion_batch_production_package_waves (
              project_id, batch_plan_id, wave_key, target_key, target_environment,
              schema_contract, max_units, max_rows, max_packages, approval_reason,
              approved_by, approved_at, approval_expires_at, actor_type, actor_id, status
            )
            select
              p.id, $1::bigint, 'sample-wave:applied', 'vamo-place-intelligence', 'production',
              'vamo-place-intelligence@1', 1, 2, 1, 'Existing delivery proof.',
              '{}'::jsonb, '2026-07-02T12:10:00.000Z'::timestamptz,
              '2026-07-02T12:25:00.000Z'::timestamptz, 'operator', 'test-admin', 'consumer_applied'
            from ingestion_platform.ingestion_projects p
            where p.project_key = 'vamo'
            returning id::text as id
          `,
          [samplePlan.rows[0]?.id]
        );
        await client.query(
          `
            insert into ingestion_platform.ingestion_batch_production_package_wave_items (
              wave_id, queue_item_id, unit_key, run_order, planned_row_count,
              schema_contract, status
            )
            values ($1::bigint, $2::bigint, $3, $4, 2, 'vamo-place-intelligence@1', 'consumer_applied')
          `,
          [
            insertedWave.rows[0]?.id,
            sampleItem.rows[0]?.id,
            sampleItem.rows[0]?.unit_key,
            sampleItem.rows[0]?.run_order
          ]
        );

        const latest = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
        assert.ok(latest);
        assert.equal(latest.planId, "vamo-eu-full-data-v1");
        assert.equal(latest.progress.total, 2);
        assert.deepEqual(latest.items[0]?.crossPlanPackageLifecycle, {
          planKey: "vamo-eu-poi-sample",
          waveKey: "sample-wave:applied",
          status: "consumer_applied"
        });

        const explicitSample = await loadBatchQueueSnapshot({
          client,
          projectKey: "vamo",
          planKey: "vamo-eu-poi-sample"
        });
        assert.ok(explicitSample);
        assert.equal(explicitSample.planId, "vamo-eu-poi-sample");
        assert.equal(explicitSample.progress.total, 36);
      } finally {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.end();
      }
    }
  );
});
