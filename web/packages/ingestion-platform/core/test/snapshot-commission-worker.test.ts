import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import {
  claimSnapshotCommissionRequest,
  completeSnapshotCommissionRequest,
  createSnapshotCommissionRequest
} from "../src/snapshot-commission-control.js";
import { snapshotCommissionOperatorErrorForCode } from "../src/snapshot-commission-errors.js";
import {
  SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
  runSnapshotCommissionWorker
} from "../src/snapshot-commission-worker.js";
import type { FsqSnapshotAcquireResult } from "../src/fsq-snapshot-acquire.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const workerModule = readFileSync("core/src/snapshot-commission-worker.ts", "utf8");
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

const planSpec = {
  kind: "ingestion.batch_plan",
  version: 1,
  id: "vamo-eu-poi-sample",
  projectKey: "vamo",
  sourceKey: "fsq-os-places-snapshot",
  targetProfileKey: "place-intelligence",
  targetKey: "vamo-place-intelligence",
  targetEnvironment: "staging",
  safetyMode: "dry_run",
  geographies: { countries: [{ key: "italy" }] },
  categories: ["poi"],
  bounds: { sampleRowLimitPerUnit: 250 }
};

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
        'staging', 'dry_run', $2::jsonb, '{}'::jsonb, 'active'
      )
      on conflict do nothing
    `,
    [project.rows[0]!.id, JSON.stringify(planSpec)]
  );
  const created = await createSnapshotCommissionRequest({
    client,
    projectKey: "vamo",
    planKey: "vamo-eu-poi-sample",
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

  it("rejects missing worker confirmation and service API key", async () => {
    const missingConfirmation = await runSnapshotCommissionWorker({
      connectionString: "postgres://example",
      workerId: "worker",
      workerRunKey: "run-1",
      serviceApiKey: "service-api-key"
    });
    assert.deepEqual(missingConfirmation, { ok: false, blocks: ["worker_confirmation_missing"] });

    const missingToken = await runSnapshotCommissionWorker({
      connectionString: "postgres://example",
      workerId: "worker",
      workerRunKey: "run-1",
      confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE
    });
    assert.deepEqual(missingToken, { ok: false, blocks: ["service_api_key_missing"] });
  });

  it(
    "claims once, replays safely, completes to activation_pending, and preserves retryable completion failures",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const owner = new Client({ connectionString: databaseUrl });
      await owner.connect();

      try {
        await owner.query("drop schema if exists ingestion_platform cascade");
        await owner.query(controlSchemaSql);
        await seedCommissionRequest(owner);

        let acquireCalls = 0;
        const successAcquire = async (): Promise<FsqSnapshotAcquireResult> => {
          acquireCalls += 1;
          return {
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
          };
        };

        const completed = await runSnapshotCommissionWorker({
          client: owner,
          connectionString: databaseUrl,
          workerId: "commission-worker",
          workerRunKey: "worker-run-success",
          confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
          serviceApiKey: "test-service-api-key",
          runAcquire: successAcquire
        });
        assert.equal(completed.ok, true);
        if (!completed.ok) return;
        assert.equal(completed.outcome, "completed");
        if (completed.outcome !== "completed") return;
        assert.equal(acquireCalls, 1);

        const replay = await runSnapshotCommissionWorker({
          client: owner,
          connectionString: databaseUrl,
          workerId: "commission-worker",
          workerRunKey: "worker-run-success",
          confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
          serviceApiKey: "test-service-api-key",
          runAcquire: successAcquire
        });
        assert.equal(replay.ok, true);
        if (!replay.ok) return;
        assert.equal(replay.outcome, "idempotent_replay");
        assert.equal(acquireCalls, 1);

        const activationRows = await owner.query<{ status: string }>(
          `
            select status
            from ingestion_platform.ingestion_snapshot_commission_requests
            where id = (
              select id from ingestion_platform.ingestion_snapshot_commission_requests
              order by id desc limit 1
            )
          `
        );
        assert.equal(activationRows.rows[0]?.status, "activation_pending");

        const bindingRows = await owner.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_snapshot_release_plan_bindings`
        );
        assert.equal(bindingRows.rows[0]?.count, "0");

        await seedCommissionRequest(owner);
        const failed = await runSnapshotCommissionWorker({
          client: owner,
          connectionString: databaseUrl,
          workerId: "commission-worker",
          workerRunKey: "worker-run-failure",
          confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
          serviceApiKey: "test-service-api-key",
          runAcquire: async () => ({ ok: false, blocks: ["provider_unavailable"] })
        });
        assert.equal(failed.ok, true);
        if (!failed.ok) return;
        assert.equal(failed.outcome, "failed");
        if (failed.outcome !== "failed") return;
        assert.equal(failed.errorCode, "acquisition_blocked");
        assert.equal(
          failed.errorMessage,
          snapshotCommissionOperatorErrorForCode("acquisition_blocked")
        );
      } finally {
        await owner.query("drop schema if exists ingestion_platform cascade");
        await owner.end();
      }
    }
  );

  it(
    "reconciles an already registered release without calling the provider again",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const owner = new Client({ connectionString: databaseUrl });
      await owner.connect();

      try {
        await owner.query("drop schema if exists ingestion_platform cascade");
        await owner.query(controlSchemaSql);
        const requestId = await seedCommissionRequest(owner);

        await claimSnapshotCommissionRequest({
          client: owner,
          workerId: "worker",
          workerRunKey: "run-reconcile",
          leaseSeconds: 120
        });

        await owner.query(
          `
            insert into ingestion_platform.ingestion_snapshot_releases (
              project_id, release_id, source_key, source_provider, status, acquired_at,
              provenance_url, input_sha256, output_sha256, source_attribution, license_identifier,
              retention_statement, intended_consumer, intended_target, artifact_key, artifact_uri,
              coverage, row_counts, metadata, updated_at
            )
            select
              p.id,
              'fsq_os_places-20260701-cafebabef00d',
              'fsq-os-places-snapshot',
              'fsq_os_places',
              'activation_ready',
              now(),
              'https://example.com',
              repeat('a', 64),
              repeat('b', 64),
              'FSQ',
              'FSQ-OS-Places',
              'Retain',
              'vamo',
              'vamo-place-intelligence',
              'fsq-os-places-snapshot/test/bundle',
              'file:///tmp/bundle',
              '{"kind":"ingestion.snapshot_coverage_report","releaseId":"fsq_os_places-20260701-cafebabef00d","derivedFromValidRowsOnly":true,"validRowCount":1,"invalidRowCount":0,"duplicateRowCount":0,"outOfScopeRowCount":0,"byCountry":{"italy":1},"byPoiType":{"poi":1}}'::jsonb,
              '{"valid":1,"invalid":0,"duplicate":0,"outOfScope":0}'::jsonb,
              jsonb_build_object('commissionRequestId', $1::text),
              now()
            from ingestion_platform.ingestion_projects p
            where p.project_key = 'vamo'
          `,
          [requestId]
        );

        await owner.query(
          `
            update ingestion_platform.ingestion_snapshot_commission_requests
            set claim_expires_at = now() - interval '1 minute'
            where id = $1::bigint
          `,
          [requestId]
        );

        let acquireCalls = 0;
        const reclaimed = await runSnapshotCommissionWorker({
          client: owner,
          connectionString: databaseUrl,
          workerId: "worker",
          workerRunKey: "run-reconcile-2",
          confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
          serviceApiKey: "test-service-api-key",
          runAcquire: async () => {
            acquireCalls += 1;
            throw new Error("provider should not be called during reconciliation");
          }
        });

        assert.equal(reclaimed.ok, true);
        if (!reclaimed.ok) return;
        assert.equal(reclaimed.outcome, "reconciled");
        assert.equal(acquireCalls, 0);

        const row = await owner.query<{ status: string; registered_release_id: string }>(
          `select status, registered_release_id from ingestion_platform.ingestion_snapshot_commission_requests where id = $1::bigint`,
          [requestId]
        );
        assert.equal(row.rows[0]?.status, "activation_pending");
        assert.equal(row.rows[0]?.registered_release_id, "fsq_os_places-20260701-cafebabef00d");
      } finally {
        await owner.query("drop schema if exists ingestion_platform cascade");
        await owner.end();
      }
    }
  );

  it("uses pending_retry for post-registration completion failures instead of marking failed", () => {
    assert.match(workerModule, /outcome: "pending_retry"/);
    assert.match(workerModule, /pendingRetryResult/);
    assert.doesNotMatch(
      workerModule,
      /finalizeCommissionRequest[\s\S]{0,400}await failRequest/
    );
  });
});
