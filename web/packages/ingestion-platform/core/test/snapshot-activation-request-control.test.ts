import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import {
  claimSnapshotActivationRequest,
  completeSnapshotActivationRequest,
  createSnapshotActivationRequest,
  hasActiveSnapshotActivationRequest,
  loadLatestSnapshotActivationRequest,
  type SnapshotActivationRequestPgClientLike
} from "../src/snapshot-activation-request-control.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const confluendoBootstrapSql = readFileSync("core/sql/control_bootstrap_confluendo.sql", "utf8");
import {
  resetDisposableTestDatabase,
  resolveDisposableTestDatabaseUrl
} from "./disposable-test-database.js";

const databaseUrl = resolveDisposableTestDatabaseUrl(process.env.INGESTION_TEST_DATABASE_URL);
const smokeProjectKey = "activation-smoke-vamo";
const smokePlanKey = "activation-smoke-plan";

describe("snapshot activation request control adapter", () => {
  it("does not reconnect a caller-provided client", async () => {
    let connectCalls = 0;
    const client = {
      connect: async () => {
        connectCalls += 1;
      },
      query: async () => ({
        rows: [{ result: { requestId: "1", auditId: "2", releaseId: "fsq-release-1" } }]
      })
    };

    const created = await createSnapshotActivationRequest({
      client: client as unknown as SnapshotActivationRequestPgClientLike,
      projectKey: smokeProjectKey,
      planKey: smokePlanKey,
      commissionRequestId: "1",
      releaseId: "fsq-release-1",
      actor: { type: "operator", id: "admin@example.com" },
      auditReason: "Activate reviewed release."
    });

    assert.equal(created.requestId, "1");
    assert.equal(connectCalls, 0);
  });
});

describe("snapshot activation request control schema", () => {
  it("declares separate request lifecycle and grants app create/read only", () => {
    assert.match(controlSchemaSql, /ingestion_snapshot_activation_requests/);
    assert.match(controlSchemaSql, /ingestion_snapshot_activation_requests_one_active_per_plan_idx/);
    assert.match(controlSchemaSql, /create_snapshot_activation_request/);
    assert.match(controlSchemaSql, /claim_snapshot_activation_request/);
    assert.match(controlSchemaSql, /complete_snapshot_activation_request/);
    assert.match(controlSchemaSql, /ingestion_snapshot_activation_requests_failure_telemetry_object/);
    assert.match(controlSchemaSql, /snapshot_activation\.failed/);
    assert.match(confluendoBootstrapSql, /grant select on ingestion_platform\.ingestion_snapshot_activation_requests/i);
    assert.match(confluendoBootstrapSql, /grant execute on function ingestion_platform\.create_snapshot_activation_request/i);
    assert.doesNotMatch(confluendoBootstrapSql, /grant execute on function ingestion_platform\.claim_snapshot_activation_request/i);
    assert.doesNotMatch(confluendoBootstrapSql, /grant execute on function ingestion_platform\.complete_snapshot_activation_request/i);
  });
});

describe("snapshot activation request control DB smoke", () => {
  it(
    "allows app create/read while leaving claim, completion, and direct updates worker-only",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const owner = new Client({ connectionString: databaseUrl });
      await owner.connect();
      try {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await resetDisposableTestDatabase(owner, databaseUrl!, { roles: ["confluendo_app"] });
        await owner.query(controlSchemaSql);
        await owner.query("create role confluendo_app login password 'test'");
        await owner.query(confluendoBootstrapSql);
        await owner.query(
          `insert into ingestion_platform.ingestion_projects (project_key, display_name) values ($1, 'Activation smoke Vamo')`,
          [smokeProjectKey]
        );
        const project = await owner.query<{ id: string }>(
          `select id::text as id from ingestion_platform.ingestion_projects where project_key = $1`,
          [smokeProjectKey]
        );
        await owner.query(
          `
            insert into ingestion_platform.ingestion_batch_plans (
              project_id, plan_key, source_key, target_key, target_environment, safety_mode, spec, plan_summary, status
            ) values ($1::bigint, $2, 'fsq-os-places-snapshot', 'vamo-place-intelligence', 'staging', 'dry_run', '{}'::jsonb, '{}'::jsonb, 'active')
          `,
          [project.rows[0]!.id, smokePlanKey]
        );
        const plan = await owner.query<{ id: string }>(
          `select id::text as id from ingestion_platform.ingestion_batch_plans where plan_key = $1`,
          [smokePlanKey]
        );
        await owner.query(
          `
            insert into ingestion_platform.ingestion_snapshot_releases (
              project_id, release_id, source_key, source_provider, status, acquired_at, provenance_url,
              input_sha256, output_sha256, source_attribution, license_identifier, retention_statement,
              intended_consumer, intended_target, artifact_key, artifact_uri
            ) values (
              $1::bigint, 'fsq-release-1', 'fsq-os-places-snapshot', 'fsq', 'activation_ready', now(),
              'https://example.test/release', repeat('a', 64), repeat('b', 64), 'FSQ Open Source Places',
              'fsq-open-source-places', 'until superseded', 'vamo', 'vamo-place-intelligence',
              'fsq/fsq-release-1/bundle', 'server://private'
            )
          `,
          [project.rows[0]!.id]
        );
        const commission = await owner.query<{ id: string }>(
          `
            insert into ingestion_platform.ingestion_snapshot_commission_requests (
              project_id, batch_plan_id, source_key, status, countries, categories, max_rows_per_scope,
              audit_reason, requested_by_type, requested_by_id, registered_release_id
            ) values ($1::bigint, $2::bigint, 'fsq-os-places-snapshot', 'activation_pending', '[]'::jsonb, '[]'::jsonb, 1, 'commission', 'operator', 'admin@example.com', 'fsq-release-1')
            returning id::text as id
          `,
          [project.rows[0]!.id, plan.rows[0]!.id]
        );

        const app = new Client({
          connectionString: databaseUrl.replace(/\/\/[^@]+@/, "//confluendo_app:test@")
        });
        await app.connect();
        try {
          const created = await createSnapshotActivationRequest({
            client: app,
            projectKey: smokeProjectKey,
            planKey: smokePlanKey,
            commissionRequestId: commission.rows[0]!.id,
            releaseId: "fsq-release-1",
            actor: { type: "operator", id: "admin@example.com" },
            auditReason: "Activate reviewed release."
          });
          assert.equal(created.status, "requested");
          assert.equal(created.releaseId, "fsq-release-1");
          assert.equal(
            await hasActiveSnapshotActivationRequest({ client: app, projectKey: smokeProjectKey, planKey: smokePlanKey }),
            true
          );
          assert.equal(
            (await loadLatestSnapshotActivationRequest({ client: app, projectKey: smokeProjectKey, planKey: smokePlanKey }))?.status,
            "requested"
          );
          await assert.rejects(
            () => app.query(`update ingestion_platform.ingestion_snapshot_activation_requests set status = 'failed'`),
            /permission denied/i
          );
        } finally {
          await app.end();
        }

        const claimed = await claimSnapshotActivationRequest({
          client: owner,
          workerId: "activation-worker",
          workerRunKey: "activation-run-1",
          leaseSeconds: 120
        });
        assert.equal(claimed.ok, true);
        if (!claimed.ok) return;
        assert.equal(claimed.request.status, "running");
        await completeSnapshotActivationRequest({
          client: owner,
          requestId: claimed.request.requestId,
          workerRunKey: "activation-run-1",
          status: "failed",
          errorCode: "activation_blocked",
          errorMessage: "A safe precondition blocked activation.",
          failureTelemetry: {
            traceId: "0ff01c4a-23fe-4b20-bd8e-0b95a1d24cf8",
            stage: "activation",
            classification: "activation_precondition_blocked"
          }
        });
        const finalRow = await owner.query<{ status: string; failure_telemetry: Record<string, unknown> }>(
          `select status, failure_telemetry from ingestion_platform.ingestion_snapshot_activation_requests where id = $1::bigint`,
          [claimed.request.requestId]
        );
        assert.equal(finalRow.rows[0]?.status, "failed");
        assert.deepEqual(finalRow.rows[0]?.failure_telemetry, {
          traceId: "0ff01c4a-23fe-4b20-bd8e-0b95a1d24cf8",
          stage: "activation",
          classification: "activation_precondition_blocked"
        });
      } finally {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await resetDisposableTestDatabase(owner, databaseUrl!, { roles: ["confluendo_app"] });
        await owner.end();
      }
    }
  );
});
