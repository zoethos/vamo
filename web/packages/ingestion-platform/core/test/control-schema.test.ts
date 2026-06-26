import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import { applyPostgresIngestionCommand } from "../src/control-command-api.js";
import {
  CONTROL_SCHEMA_NAME,
  CONTROL_TABLES,
  controlTableRef
} from "../src/control-models.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

describe("ingestion control schema", () => {
  it("declares only platform-owned ingestion tables", () => {
    assert.equal(CONTROL_SCHEMA_NAME, "ingestion_platform");
    assert.equal(CONTROL_TABLES.length, 17);

    for (const table of CONTROL_TABLES) {
      assert.match(table, /^ingestion_[a-z0-9_]+$/);
      assert.doesNotMatch(table, /vamo|trip|place_intelligence|location_/);
      assert.deepEqual(controlTableRef(table), {
        schema: "ingestion_platform",
        table
      });
    }
  });

  it("keeps Vamo product table names out of the SQL artifact", () => {
    assert.doesNotMatch(controlSchemaSql, /\bvamo\b/i);
    assert.doesNotMatch(controlSchemaSql, /\btrips?\b/i);
    assert.doesNotMatch(controlSchemaSql, /\blocation_canonicals\b/i);
    assert.doesNotMatch(controlSchemaSql, /\blocation_source_refs\b/i);
  });

  it(
    "applies to disposable Postgres, enforces uniqueness, and applies command mutations",
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
        assert.deepEqual(
          tables.rows.map((row) => row.table_name),
          [...CONTROL_TABLES].sort()
        );

        const projectId = await insertReturningId(
          client,
          `
            insert into ingestion_platform.ingestion_projects (project_key, display_name)
            values ('demo', 'Demo Project')
          `
        );
        const specId = await insertReturningId(
          client,
          `
            insert into ingestion_platform.ingestion_specs (
              project_id,
              spec_key,
              spec_kind,
              revision,
              content,
              content_sha256,
              status
            )
            values ($1, 'places-pipeline', 'pipeline', 1, '{"kind":"pipeline"}', 'hash-1', 'active')
          `,
          [projectId]
        );
        const sourceId = await insertReturningId(
          client,
          `
            insert into ingestion_platform.ingestion_sources (
              project_id,
              source_key,
              display_name,
              adapter
            )
            values ($1, 'fixture-source', 'Fixture Source', 'fixture')
          `,
          [projectId]
        );
        const targetId = await insertReturningId(
          client,
          `
            insert into ingestion_platform.ingestion_targets (
              project_id,
              target_key,
              display_name,
              adapter
            )
            values ($1, 'warehouse', 'Warehouse', 'postgres')
          `,
          [projectId]
        );
        const runId = await insertReturningId(
          client,
          `
            insert into ingestion_platform.ingestion_runs (
              project_id,
              spec_id,
              run_key,
              status
            )
            values ($1, $2, 'run-1', 'running')
          `,
          [projectId, specId]
        );
        const queuedTaskId = await insertReturningId(
          client,
          `
            insert into ingestion_platform.ingestion_tasks (
              project_id,
              run_id,
              source_id,
              target_id,
              task_key,
              status
            )
            values ($1, $2, $3, $4, 'task-start', 'queued')
          `,
          [projectId, runId, sourceId, targetId]
        );
        const runningTaskId = await insertReturningId(
          client,
          `
            insert into ingestion_platform.ingestion_tasks (
              project_id,
              run_id,
              source_id,
              target_id,
              task_key,
              status
            )
            values ($1, $2, $3, $4, 'task-shutdown', 'running')
          `,
          [projectId, runId, sourceId, targetId]
        );
        const failedTaskId = await insertReturningId(
          client,
          `
            insert into ingestion_platform.ingestion_tasks (
              project_id,
              run_id,
              source_id,
              target_id,
              task_key,
              status,
              error_code,
              error_message
            )
            values ($1, $2, $3, $4, 'task-reset', 'failed', 'fixture_error', 'needs review')
          `,
          [projectId, runId, sourceId, targetId]
        );

        await client.query(
          `
            insert into ingestion_platform.ingestion_checkpoints (
              project_id,
              pipeline_spec_id,
              source_id,
              target_id,
              cursor_scope,
              cursor_strategy,
              cursor_value,
              updated_by_run_id
            )
            values ($1, $2, $3, $4, 'default', 'monotonic_row_id', '{"last":1}', $5)
          `,
          [projectId, specId, sourceId, targetId, runId]
        );
        await assertUniqueViolation(
          client.query(
            `
              insert into ingestion_platform.ingestion_checkpoints (
                project_id,
                pipeline_spec_id,
                source_id,
                target_id,
                cursor_scope,
                cursor_strategy,
                cursor_value
              )
              values ($1, $2, $3, $4, 'default', 'monotonic_row_id', '{"last":2}')
            `,
            [projectId, specId, sourceId, targetId]
          )
        );

        await client.query(
          `
            insert into ingestion_platform.ingestion_events (
              project_id,
              run_id,
              task_id,
              event_type,
              severity,
              signal,
              message
            )
            values ($1, $2, $3, 'task_stopped', 'warn', 'worker_exit', 'Worker exited.')
          `,
          [projectId, runId, runningTaskId]
        );

        const shutdownLeaseId = await insertReturningId(
          client,
          `
            insert into ingestion_platform.ingestion_worker_leases (
              task_id,
              worker_id,
              lease_token,
              expires_at
            )
            values ($1, 'worker-smoke', 'lease-token-smoke', now() + interval '1 minute')
          `,
          [runningTaskId]
        );
        const resetLeaseId = await insertReturningId(
          client,
          `
            insert into ingestion_platform.ingestion_worker_leases (
              task_id,
              worker_id,
              lease_token,
              expires_at
            )
            values ($1, 'worker-reset-smoke', 'lease-token-reset-smoke', now() + interval '1 minute')
          `,
          [failedTaskId]
        );

        const startResult = await applyPostgresIngestionCommand({
          client,
          projectKey: "demo",
          command: "start",
          scope: { type: "task", taskId: String(queuedTaskId) },
          actor: { type: "api", id: "db-smoke" },
          claimedActorId: "operator-smoke",
          now: "2026-06-26T12:00:00.000Z"
        });

        assert.equal(startResult.ok, true);
        assert.deepEqual(startResult.appliedTaskPatchIds, [String(queuedTaskId)]);

        const shutdownResult = await applyPostgresIngestionCommand({
          client,
          projectKey: "demo",
          command: "shutdown",
          scope: { type: "task", taskId: String(runningTaskId) },
          actor: { type: "api", id: "db-smoke" },
          claimedActorId: "operator-smoke",
          now: "2026-06-26T12:01:00.000Z"
        });

        assert.equal(shutdownResult.ok, true);
        assert.deepEqual(shutdownResult.appliedTaskPatchIds, [String(runningTaskId)]);
        assert.deepEqual(shutdownResult.appliedLeasePatchIds, [String(shutdownLeaseId)]);

        const resetResult = await applyPostgresIngestionCommand({
          client,
          projectKey: "demo",
          command: "reset",
          scope: { type: "task", taskId: String(failedTaskId) },
          actor: { type: "api", id: "db-smoke" },
          claimedActorId: "operator-smoke",
          now: "2026-06-26T12:02:00.000Z",
          reason: "db smoke reset"
        });

        assert.equal(resetResult.ok, true);
        assert.deepEqual(resetResult.appliedTaskPatchIds, [String(failedTaskId)]);
        assert.deepEqual(resetResult.appliedLeasePatchIds, [String(resetLeaseId)]);

        const commandRows = await client.query<{
          task_key: string;
          task_status: string;
          lease_status: string;
          release_reason: string | null;
          error_code: string | null;
          error_message: string | null;
          actor_type: string;
          actor_id: string | null;
          action: string;
          payload: {
            accepted?: boolean;
            claimedActorId?: string;
            appliedTaskPatchIds?: string[];
            appliedLeasePatchIds?: string[];
          };
        }>(
          `
            select
              task.task_key,
              task.status as task_status,
              task.error_code,
              task.error_message,
              lease.status as lease_status,
              lease.release_reason,
              audit.actor_type,
              audit.actor_id,
              audit.action,
              audit.payload
            from ingestion_platform.ingestion_tasks task
            left join ingestion_platform.ingestion_worker_leases lease
              on lease.task_id = task.id
            join ingestion_platform.ingestion_audit_log audit
              on audit.project_id = task.project_id
             and audit.payload->'appliedTaskPatchIds' ? task.id::text
            where task.id in ($1, $2, $3)
              and audit.action in ('ingestion.start', 'ingestion.shutdown', 'ingestion.reset')
            order by task.task_key
          `,
          [queuedTaskId, runningTaskId, failedTaskId]
        );
        const rowsByTaskKey = new Map(commandRows.rows.map((row) => [row.task_key, row]));
        const startedRow = rowsByTaskKey.get("task-start");
        const shutdownRow = rowsByTaskKey.get("task-shutdown");
        const resetRow = rowsByTaskKey.get("task-reset");

        assert.ok(startedRow);
        assert.equal(startedRow.task_status, "running");
        assert.equal(startedRow.action, "ingestion.start");
        assert.equal(startedRow.actor_type, "api");
        assert.equal(startedRow.actor_id, "db-smoke");
        assert.equal(startedRow.payload.accepted, true);
        assert.equal(startedRow.payload.claimedActorId, "operator-smoke");
        assert.deepEqual(startedRow.payload.appliedTaskPatchIds, [String(queuedTaskId)]);

        assert.ok(shutdownRow);
        assert.equal(shutdownRow.task_status, "paused");
        assert.equal(shutdownRow.lease_status, "released");
        assert.equal(shutdownRow.release_reason, "operator_shutdown");
        assert.equal(shutdownRow.action, "ingestion.shutdown");
        assert.equal(shutdownRow.payload.accepted, true);
        assert.deepEqual(shutdownRow.payload.appliedTaskPatchIds, [String(runningTaskId)]);
        assert.deepEqual(shutdownRow.payload.appliedLeasePatchIds, [String(shutdownLeaseId)]);

        assert.ok(resetRow);
        assert.equal(resetRow.task_status, "queued");
        assert.equal(resetRow.error_code, null);
        assert.equal(resetRow.error_message, null);
        assert.equal(resetRow.lease_status, "released");
        assert.equal(resetRow.release_reason, "operator_reset");
        assert.equal(resetRow.action, "ingestion.reset");
        assert.equal(resetRow.payload.accepted, true);
        assert.deepEqual(resetRow.payload.appliedTaskPatchIds, [String(failedTaskId)]);
        assert.deepEqual(resetRow.payload.appliedLeasePatchIds, [String(resetLeaseId)]);

        const shipmentId = await insertReturningId(
          client,
          `
            insert into ingestion_platform.ingestion_shipments (
              project_id,
              run_id,
              target_id,
              shipment_key,
              mode,
              status
            )
            values ($1, $2, $3, 'shipment-1', 'dry_run', 'planned')
          `,
          [projectId, runId, targetId]
        );
        await client.query(
          `
            insert into ingestion_platform.ingestion_shipment_items (
              shipment_id,
              target_table,
              operation,
              idempotency_key,
              record_key
            )
            values ($1, 'generic_records', 'insert', 'target:1', 'record-1')
          `,
          [shipmentId]
        );
        await assertUniqueViolation(
          client.query(
            `
              insert into ingestion_platform.ingestion_shipment_items (
                shipment_id,
                target_table,
                operation,
                idempotency_key,
                record_key
              )
              values ($1, 'generic_records', 'insert', 'target:1', 'record-1-copy')
            `,
            [shipmentId]
          )
        );
      } finally {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.end();
      }
    }
  );
});

async function insertReturningId(
  client: Client,
  sql: string,
  values: unknown[] = []
): Promise<number> {
  const result = await client.query<{ id: string }>(`${sql} returning id`, values);
  return Number(result.rows[0]?.id);
}

async function assertUniqueViolation(promise: Promise<unknown>): Promise<void> {
  await assert.rejects(promise, (error: unknown) => {
    return typeof error === "object" && error !== null && "code" in error && error.code === "23505";
  });
}
