import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import {
  claimSnapshotCommissionRequest,
  createSnapshotCommissionRequest
} from "../src/snapshot-commission-control.js";
import {
  SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
  runSnapshotCommissionWorker
} from "../src/snapshot-commission-worker.js";
import type { FsqSnapshotAcquireResult } from "../src/fsq-snapshot-acquire.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const workerModule = readFileSync("core/src/snapshot-commission-worker.ts", "utf8");
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

async function seedCommissionRequest(client: Client): Promise<string> {
  await client.query(
    `
      insert into ingestion_platform.ingestion_projects (project_key, display_name)
      values ('vamo', 'Vamo')
      on conflict do nothing
    `
  );
  const project = await client.query<{ id: string }>(
    `select id::text as id from ingestion_platform.ingestion_projects where project_key = 'vamo'`
  );
  await client.query(
    `
      insert into ingestion_platform.ingestion_batch_plans (
        project_id, plan_key, source_key, target_key, target_environment, safety_mode, spec, plan_summary, status
      ) values (
        $1::bigint, 'vamo-eu-poi-sample', 'fsq-os-places-snapshot', 'vamo-place-intelligence',
        'staging', 'dry_run', '{}'::jsonb, '{}'::jsonb, 'active'
      )
      on conflict do nothing
    `,
    [project.rows[0]!.id]
  );
  const created = await createSnapshotCommissionRequest({
    client,
    projectKey: "vamo",
    planKey: "vamo-eu-poi-sample",
    sourceKey: "fsq-os-places-snapshot",
    countries: ["italy"],
    categories: ["poi"],
    maxRowsPerScope: 250,
    actor: { type: "operator", id: "dba@example.com" },
    auditReason: "Worker smoke commissioning request."
  });
  return created.requestId;
}

describe("runSnapshotCommissionWorker", () => {
  it("never imports activation paths", () => {
    assert.doesNotMatch(workerModule, /runSnapshotReleaseActivation/);
    assert.doesNotMatch(workerModule, /activateSnapshotRelease/);
  });

  it("rejects missing worker confirmation and catalog token", async () => {
    const missingConfirmation = await runSnapshotCommissionWorker({
      connectionString: "postgres://example",
      workerId: "worker",
      workerRunKey: "run-1",
      catalogToken: "token"
    });
    assert.deepEqual(missingConfirmation, { ok: false, blocks: ["worker_confirmation_missing"] });

    const missingToken = await runSnapshotCommissionWorker({
      connectionString: "postgres://example",
      workerId: "worker",
      workerRunKey: "run-1",
      confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE
    });
    assert.deepEqual(missingToken, { ok: false, blocks: ["catalog_token_missing"] });
  });

  it(
    "claims once, replays safely, completes to activation_pending, and records failures",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const owner = new Client({ connectionString: databaseUrl });
      await owner.connect();

      try {
        await owner.query("drop schema if exists ingestion_platform cascade");
        await owner.query(controlSchemaSql);
        await seedCommissionRequest(owner);

        const successAcquire = async (): Promise<FsqSnapshotAcquireResult> => ({
          ok: true,
          result: {
            mode: "execute",
            accepted: true,
            releaseId: "fsq_os_places-20260701-deadbeefcafe",
            artifactKey:
              "fsq-os-places-snapshot/fsq_os_places-20260701-deadbeefcafe/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            artifactUri: "file:///tmp/example",
            bundleSha256: "b".repeat(64),
            inputSha256: "a".repeat(64),
            outputSha256: "c".repeat(64),
            coverage: {
              kind: "ingestion.snapshot_coverage_report",
              releaseId: "fsq_os_places-20260701-deadbeefcafe",
              derivedFromValidRowsOnly: true,
              validRowCount: 2,
              invalidRowCount: 0,
              duplicateRowCount: 0,
              outOfScopeRowCount: 0,
              byCountry: { italy: 2 },
              byPoiType: { poi: 2 }
            },
            issues: [],
            nextAction: "Run ip18:snapshot-activate separately."
          }
        });

        const completed = await runSnapshotCommissionWorker({
          client: owner,
          connectionString: databaseUrl,
          workerId: "commission-worker",
          workerRunKey: "worker-run-success",
          confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
          catalogToken: "test-token",
          runAcquire: successAcquire
        });
        assert.equal(completed.ok, true);
        if (!completed.ok) return;
        assert.equal(completed.outcome, "completed");
        if (completed.outcome !== "completed") return;
        assert.equal(completed.registeredReleaseId, "fsq_os_places-20260701-deadbeefcafe");
        assert.equal(completed.releaseStatus, "activation_pending");

        const replay = await runSnapshotCommissionWorker({
          client: owner,
          connectionString: databaseUrl,
          workerId: "commission-worker",
          workerRunKey: "worker-run-success",
          confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
          catalogToken: "test-token",
          runAcquire: successAcquire
        });
        assert.equal(replay.ok, true);
        if (!replay.ok) return;
        assert.equal(replay.outcome, "idempotent_replay");

        const activationRows = await owner.query<{ status: string }>(
          `
            select status
            from ingestion_platform.ingestion_snapshot_release_plan_bindings
          `
        );
        assert.equal(activationRows.rowCount, 0);

        await seedCommissionRequest(owner);
        const failed = await runSnapshotCommissionWorker({
          client: owner,
          connectionString: databaseUrl,
          workerId: "commission-worker",
          workerRunKey: "worker-run-failure",
          confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
          catalogToken: "test-token",
          runAcquire: async () => ({ ok: false, blocks: ["provider_unavailable"] })
        });
        assert.equal(failed.ok, true);
        if (!failed.ok) return;
        assert.equal(failed.outcome, "failed");
        if (failed.outcome !== "failed") return;
        assert.equal(failed.errorCode, "acquisition_blocked");

        const claimedTwice = await claimSnapshotCommissionRequest({
          client: owner,
          workerId: "commission-worker",
          workerRunKey: "worker-run-failure"
        });
        assert.equal(claimedTwice.ok, false);
      } finally {
        await owner.query("drop schema if exists ingestion_platform cascade");
        await owner.end();
      }
    }
  );
});
