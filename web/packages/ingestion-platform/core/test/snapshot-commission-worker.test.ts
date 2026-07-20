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
const workerScript = readFileSync("scripts/run-ip18-snapshot-commission-worker.mjs", "utf8");
import {
  resetDisposableTestDatabase,
  resolveDisposableTestDatabaseUrl
} from "./disposable-test-database.js";

const databaseUrl = resolveDisposableTestDatabaseUrl(process.env.INGESTION_TEST_DATABASE_URL);

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
  bounds: { sampleRowLimitPerUnit: 250 },
  sourceTaxonomy: {
    provider: "fsq_os_places",
    fallbackConsumerCategory: "poi",
    mappings: [
      {
        providerCategoryIds: ["4d4b7104d754a06370d81259"],
        providerCategoryLabels: ["Arts and Entertainment"],
        consumerCategory: "poi",
        precedence: 10
      }
    ]
  }
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

  it("makes failed and retryable worker outcomes visible to job runners", () => {
    assert.match(workerScript, /result\.outcome === "failed"/);
    assert.match(workerScript, /result\.outcome === "pending_retry"/);
    assert.match(workerScript, /process\.exitCode = 1/);
    assert.match(workerScript, /resolveFsqPortalQueryTimeoutMs/);
    assert.match(workerScript, /--require-hosted-artifact-store/);
    assert.match(workerScript, /requireHostedStore: requireHostedArtifactStore/);
    assert.match(workerScript, /process\.exit\(process\.exitCode \?\? 0\)/);
    assert.match(workerModule, /traceId: failureTelemetry\.traceId/);
    assert.match(workerModule, /Snapshot commission worker acquisition failed/, "raw worker errors retain a trace ID in trusted logs");
  });

  it("rejects missing worker confirmation and portal access token", async () => {
    const missingConfirmation = await runSnapshotCommissionWorker({
      connectionString: "postgres://example",
      workerId: "worker",
      workerRunKey: "run-1",
      portalAccessToken: "portal-access-token"
    });
    assert.deepEqual(missingConfirmation, { ok: false, blocks: ["worker_confirmation_missing"] });

    const missingPortalToken = await runSnapshotCommissionWorker({
      connectionString: "postgres://example",
      workerId: "worker",
      workerRunKey: "run-1",
      confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE
    });
    assert.deepEqual(missingPortalToken, { ok: false, blocks: ["portal_access_token_missing"] });
  });

  it("refuses an expired Portal token before it claims a commissioning request", async () => {
    const result = await runSnapshotCommissionWorker({
      connectionString: "postgres://example",
      workerId: "worker",
      workerRunKey: "run-expired-token",
      confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
      portalAccessToken: "portal-access-token",
      portalAccessTokenExpiresAt: "2026-07-01T00:00:00.000Z",
      now: "2026-07-01T00:00:00.000Z"
    });
    assert.deepEqual(result, { ok: false, blocks: ["portal_access_token_expired"] });
  });

  it(
    "claims once, replays safely, completes to activation_pending, and preserves retryable completion failures",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const owner = new Client({ connectionString: databaseUrl });
      await owner.connect();

      try {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
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
                byPoiType: { poi: 2 },
                byCountryAndPoiType: { italy: { poi: 2 } }
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
          portalAccessToken: "test-portal-access-token",
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
          portalAccessToken: "test-portal-access-token",
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
          portalAccessToken: "test-portal-access-token",
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

        const failedRequestRows = await owner.query<{
          status: string;
          error_code: string;
          failure_telemetry: {
            traceId?: string;
            stage?: string;
            classification?: string;
          };
        }>(
          `
            select status, error_code, failure_telemetry
            from ingestion_platform.ingestion_snapshot_commission_requests
            order by id desc
            limit 1
          `
        );
        const failedRequest = failedRequestRows.rows[0];
        assert.equal(failedRequest?.status, "failed");
        assert.equal(failedRequest?.error_code, "acquisition_blocked");
        assert.match(failedRequest?.failure_telemetry.traceId ?? "", /^[a-f0-9-]{36}$/i);
        assert.equal(failedRequest?.failure_telemetry.stage, "worker");
        assert.equal(failedRequest?.failure_telemetry.classification, "provider_unavailable");

        const failureEventRows = await owner.query<{
          event_type: string;
          severity: string;
          signal: string | null;
          payload: {
            traceId?: string;
            stage?: string;
            classification?: string;
          };
        }>(
          `
            select event_type, severity, signal, payload
            from ingestion_platform.ingestion_events
            where event_type = 'snapshot_commission.failed'
            order by id desc
            limit 1
          `
        );
        const failureEvent = failureEventRows.rows[0];
        assert.equal(failureEvent?.event_type, "snapshot_commission.failed");
        assert.equal(failureEvent?.severity, "error");
        assert.equal(failureEvent?.signal, "acquisition_blocked");
        assert.equal(failureEvent?.payload.traceId, failedRequest?.failure_telemetry.traceId);
        assert.equal(failureEvent?.payload.stage, "worker");
        assert.equal(failureEvent?.payload.classification, "provider_unavailable");
      } finally {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
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
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
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
              '{"kind":"ingestion.snapshot_coverage_report","releaseId":"fsq_os_places-20260701-cafebabef00d","derivedFromValidRowsOnly":true,"validRowCount":1,"invalidRowCount":0,"duplicateRowCount":0,"outOfScopeRowCount":0,"byCountry":{"italy":1},"byPoiType":{"poi":1},"byCountryAndPoiType":{"italy":{"poi":1}}}'::jsonb,
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
          portalAccessToken: "test-portal-access-token",
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
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
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
