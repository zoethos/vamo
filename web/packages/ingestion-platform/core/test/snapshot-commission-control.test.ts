import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";
import { Client } from "pg";

import {
  claimSnapshotCommissionRequest,
  completeSnapshotCommissionRequest,
  createSnapshotCommissionRequest,
  hasActiveSnapshotCommissionRequest,
  loadLatestSnapshotCommissionRequest
} from "../src/snapshot-commission-control.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const confluendoBootstrapSql = readFileSync(
  "core/sql/control_bootstrap_confluendo.sql",
  "utf8"
);
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const commissionRoute = join(
  webRoot,
  "apps/confluendo-console/app/api/admin/ingestion/snapshot-commission/request/route.ts"
);
const commissionControl = join(
  webRoot,
  "apps/confluendo-console/app/admin/ingestion/snapshot-commission-control.tsx"
);

async function seedProjectAndPlan(client: Client): Promise<{ planKey: string }> {
  const project = await client.query<{ id: string }>(
    `
      insert into ingestion_platform.ingestion_projects (project_key, display_name)
      values ('vamo', 'Vamo')
      returning id::text as id
    `
  );
  await client.query(
    `
      insert into ingestion_platform.ingestion_batch_plans (
        project_id, plan_key, source_key, target_key, target_environment, safety_mode, spec, plan_summary, status
      ) values (
        $1::bigint, 'vamo-eu-poi-sample', 'fsq-os-places-snapshot', 'vamo-place-intelligence',
        'staging', 'dry_run', '{}'::jsonb, '{}'::jsonb, 'active'
      )
    `,
    [project.rows[0]!.id]
  );
  return { planKey: "vamo-eu-poi-sample" };
}

describe("snapshot commission control schema", () => {
  it("declares commission table and security-definer functions", () => {
    assert.match(controlSchemaSql, /ingestion_snapshot_commission_requests/);
    assert.match(controlSchemaSql, /create_snapshot_commission_request/);
    assert.match(controlSchemaSql, /claim_snapshot_commission_request/);
    assert.match(controlSchemaSql, /complete_snapshot_commission_request/);
    assert.match(confluendoBootstrapSql, /grant select on ingestion_platform\.ingestion_snapshot_commission_requests/i);
    assert.match(confluendoBootstrapSql, /grant execute on function ingestion_platform\.create_snapshot_commission_request/i);
    assert.doesNotMatch(
      confluendoBootstrapSql,
      /grant execute on function ingestion_platform\.claim_snapshot_commission_request/i
    );
    assert.doesNotMatch(
      confluendoBootstrapSql,
      /grant execute on function ingestion_platform\.complete_snapshot_commission_request/i
    );
  });
});

describe("snapshot commission control DB smoke", () => {
  it(
    "allows app create/read and blocks direct state updates plus worker-only functions",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const owner = new Client({ connectionString: databaseUrl });
      await owner.connect();

      try {
        await owner.query("drop schema if exists ingestion_platform cascade");
        await owner.query("drop role if exists confluendo_app");
        await owner.query(controlSchemaSql);
        await owner.query("create role confluendo_app login password 'test'");
        await owner.query(confluendoBootstrapSql);
        await seedProjectAndPlan(owner);

        const app = new Client({
          connectionString: databaseUrl.replace(/\/\/[^@]+@/, "//confluendo_app:test@")
        });
        await app.connect();

        try {
          const created = await createSnapshotCommissionRequest({
            client: app,
            projectKey: "vamo",
            planKey: "vamo-eu-poi-sample",
            sourceKey: "fsq-os-places-snapshot",
            countries: ["italy"],
            categories: ["poi"],
            maxRowsPerScope: 250,
            actor: { type: "operator", id: "dba@example.com" },
            auditReason: "Commission bounded snapshot release."
          });
          assert.equal(created.status, "requested");
          assert.ok(created.requestId);

          const latest = await loadLatestSnapshotCommissionRequest({
            client: app,
            projectKey: "vamo",
            planKey: "vamo-eu-poi-sample"
          });
          assert.equal(latest?.status, "requested");
          assert.equal(latest?.countries.join(","), "italy");

          assert.equal(
            await hasActiveSnapshotCommissionRequest({
              client: app,
              projectKey: "vamo",
              planKey: "vamo-eu-poi-sample"
            }),
            true
          );

          await assert.rejects(
            () =>
              app.query(
                `
                  update ingestion_platform.ingestion_snapshot_commission_requests
                  set status = 'failed'
                  where id = $1::bigint
                `,
                [created.requestId]
              ),
            /permission denied/i
          );

          await assert.rejects(
            () =>
              app.query(
                `select ingestion_platform.claim_snapshot_commission_request('worker', 'run-1')`
              ),
            /permission denied/i
          );

          await assert.rejects(
            () =>
              app.query(
                `
                  select ingestion_platform.complete_snapshot_commission_request(
                    $1::bigint, 'run-1', 'failed', null, 'blocked', 'blocked'
                  )
                `,
                [created.requestId]
              ),
            /permission denied/i
          );
        } finally {
          await app.end();
        }

        const claimed = await claimSnapshotCommissionRequest({
          client: owner,
          workerId: "commission-worker",
          workerRunKey: "run-smoke-1"
        });
        assert.equal(claimed.ok, true);
        if (!claimed.ok) return;
        assert.equal(claimed.request.status, "running");
        assert.equal(claimed.idempotentReplay, false);

        const replay = await claimSnapshotCommissionRequest({
          client: owner,
          workerId: "commission-worker",
          workerRunKey: "run-smoke-1"
        });
        assert.equal(replay.ok, true);
        if (!replay.ok) return;
        assert.equal(replay.idempotentReplay, true);

        await completeSnapshotCommissionRequest({
          client: owner,
          requestId: claimed.request.requestId,
          workerRunKey: "run-smoke-1",
          status: "release_registered",
          registeredReleaseId: "fsq_os_places-20260701-deadbeefcafe"
        });

        const completed = await completeSnapshotCommissionRequest({
          client: owner,
          requestId: claimed.request.requestId,
          workerRunKey: "run-smoke-1",
          status: "activation_pending",
          registeredReleaseId: "fsq_os_places-20260701-deadbeefcafe"
        });
        assert.equal(completed.status, "activation_pending");
      } finally {
        await owner.query("drop schema if exists ingestion_platform cascade");
        await owner.query("drop role if exists confluendo_app");
        await owner.end();
      }
    }
  );
});

describe("snapshot commission route artifact", () => {
  it("uses core adapters and avoids provider, artifact, and consumer write paths", () => {
    const routeSource = readFileSync(commissionRoute, "utf8");
    assert.match(routeSource, /createSnapshotCommissionRequest/);
    assert.match(routeSource, /evaluateSnapshotCommissionRequestCreate/);
    assert.match(routeSource, /parseSnapshotCommissionRequestCreate/);
    assert.match(routeSource, /INGESTION_CONTROL_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /runFsqSnapshotAcquire/);
    assert.doesNotMatch(routeSource, /FSQ_OS_PLACES_CATALOG_TOKEN/);
    assert.doesNotMatch(routeSource, /CONFLUENDO_SNAPSHOT_ARTIFACT_S3_BUCKET/);
    assert.doesNotMatch(routeSource, /VAMO_STAGING_CANARY_APP_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /VAMO_PRODUCTION_INBOX_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /runSnapshotReleaseActivation/);
    assert.doesNotMatch(routeSource, /activateSnapshotRelease/);
  });

  it("does not expose execute acquisition from the browser control", () => {
    const controlSource = readFileSync(commissionControl, "utf8");
    assert.match(controlSource, /snapshot-commission\/request/);
    assert.doesNotMatch(controlSource, /runFsqSnapshotAcquire/);
    assert.doesNotMatch(controlSource, /FSQ_OS_PLACES_CATALOG_TOKEN/);
    assert.doesNotMatch(controlSource, /Execute acquisition/i);
    assert.match(controlSource, /trusted worker/i);
  });
});
