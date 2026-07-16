import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { sampleVamoEuPoiBatchYaml } from "../src/batch-plan-read-model.js";
import {
  buildBatchQueueSnapshotFromItems,
  sampleVamoEuPoiBatchQueueSnapshot
} from "../src/batch-queue-read-model.js";
import { evaluateBatchDryRunExecution } from "../src/batch-dry-run-execution-policy.js";
import {
  deriveSimulationCountsFromQueueItem,
  executeBatchDryRun
} from "../src/batch-dry-run-execution.js";
import { simulateBatchDryRunUnit } from "../src/batch-dry-run-simulator.js";
import { loadBatchQueueSnapshot } from "../src/batch-queue-control-read.js";
import { persistBatchQueueSnapshot } from "../src/batch-queue-control.js";
import { scheduleBatchDryRun } from "../src/batch-queue-mutations.js";
import { CONTROL_TABLES } from "../src/control-models.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
import {
  resetDisposableTestDatabase,
  resolveDisposableTestDatabaseUrl
} from "./disposable-test-database.js";

const databaseUrl = resolveDisposableTestDatabaseUrl(process.env.INGESTION_TEST_DATABASE_URL);

describe("batch dry-run execution control", () => {
  it("uses provided fixture candidate and target-row counts instead of hash-derived counts", () => {
    const report = simulateBatchDryRunUnit({
      executionKey: "dry-run:test",
      unitKey: "vamo-place-intelligence:paris-france:landmark",
      geography: "paris-france",
      category: "landmark",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      candidateCount: 1,
      targetWriteCount: 2,
      rowLimit: 50,
      now: "2026-07-03T10:00:00.000Z"
    });

    assert.equal(report.rowsProcessed, 1);
    assert.equal(report.insertCount, 2);
    assert.equal(report.updateCount, 0);
    assert.equal(report.noOpCount, 0);
    assert.equal(report.wroteToTarget, false);
  });

  it("derives full-data Vamo dry-run counts from bounded proposals", () => {
    const counts = deriveSimulationCountsFromQueueItem({
      unitKey: "vamo-place-intelligence:barcelona-spain:landmark",
      runOrder: 1,
      geography: "barcelona-spain",
      geographyKind: "city",
      country: "spain",
      category: "landmark",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      sourceKey: "fsq-os-places-snapshot",
      priority: 0,
      status: "dry_run_ready",
      blockReasons: [],
      proposal: {
        scope: {
          geography: "barcelona-spain",
          category: "landmark",
          rowLimit: 1
        },
        quotaBudget: {
          maxRows: 1
        }
      }
    });

    assert.deepEqual(counts, {
      candidateCount: 1,
      targetWriteCount: 2,
      rowLimit: 1
    });
  });

  it("leaves unproposed dry-run units on the legacy deterministic simulator path", () => {
    const counts = deriveSimulationCountsFromQueueItem({
      unitKey: "vamo-place-intelligence:barcelona-spain:landmark",
      runOrder: 1,
      geography: "barcelona-spain",
      geographyKind: "city",
      country: "spain",
      category: "landmark",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      sourceKey: "fsq-os-places-sample",
      priority: 0,
      status: "dry_run_ready",
      blockReasons: []
    });

    assert.deepEqual(counts, {});
  });

  it(
    "executes bounded dry-run units idempotently and reloads reports",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetDisposableTestDatabase(client, databaseUrl!, { schemas: ["ingestion_platform"] });
        await client.query(controlSchemaSql);
        assert.equal(CONTROL_TABLES.length, 31);

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

        const scheduledSnapshot = buildBatchQueueSnapshotFromItems({
          planId: "vamo-eu-poi-sample",
          projectKey: "vamo",
          targetKey: "vamo-place-intelligence",
          targetEnvironment: "staging",
          sourceKey: "fsq-os-places-sample",
          safetyMode: "dry_run",
          items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) => ({
            ...item,
            status: "ready_for_dry_run"
          }))
        });

        await persistBatchQueueSnapshot({
          client,
          projectKey: "vamo",
          snapshot: scheduledSnapshot,
          spec: parsed.spec
        });

        await scheduleBatchDryRun({
          client,
          projectKey: "vamo",
          planId: "vamo-eu-poi-sample",
          targetKey: "vamo-place-intelligence",
          actor: { type: "operator", id: "operator-smoke" },
          reason: "IP-18.3 schedule for execution smoke",
          payload: { auditId: "15" }
        });

        const loaded = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
        assert.ok(loaded);
        assert.equal(loaded.progress.execution.dryRunReady, 36);

        const decision = evaluateBatchDryRunExecution({
          projectKey: "vamo",
          snapshot: loaded,
          targetKey: "vamo-place-intelligence",
          targetEnvironment: "staging",
          maxUnits: 2,
          auditReason: "IP-18.4 bounded dry-run execution smoke",
          auditId: "15",
          actor: { type: "operator", id: "operator-smoke" }
        });
        assert.equal(decision.ok, true);
        if (!decision.ok) {
          throw new Error("execution policy should accept scheduled units");
        }

        const first = await executeBatchDryRun({
          client,
          projectKey: "vamo",
          plan: decision.plan,
          now: "2026-07-02T14:00:00.000Z"
        });
        assert.equal(first.idempotentReplay, false);
        assert.equal(first.succeededCount, 2);

        const executionCount = await client.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_batch_dry_run_executions`
        );
        assert.equal(executionCount.rows[0]?.count, "1");

        const second = await executeBatchDryRun({
          client,
          projectKey: "vamo",
          plan: decision.plan,
          now: "2026-07-02T14:05:00.000Z"
        });
        assert.equal(second.idempotentReplay, true);
        assert.equal(second.succeededCount, 2);

        const after = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
        assert.ok(after);
        assert.equal(after.progress.execution.dryRunSucceeded, 2);
        assert.equal(after.progress.execution.dryRunReady, 34);
        assert.ok(after.latestExecution);
        assert.equal(after.latestExecution.auditId, "15");
        const succeeded = after.items.filter((item) => item.status === "dry_run_succeeded");
        assert.equal(succeeded.length, 2);
        assert.ok(succeeded[0]?.dryRunReport);
        assert.equal(succeeded[0]?.dryRunReport?.wroteToTarget, false);
        assert.equal(succeeded[0]?.targetKey, "vamo-place-intelligence");
      } finally {
        await resetDisposableTestDatabase(client, databaseUrl!, { schemas: ["ingestion_platform"] });
        await client.end();
      }
    }
  );
});
