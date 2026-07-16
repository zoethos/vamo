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
  findSnapshotReleaseIdForCommissionRequest,
  hasActiveSnapshotCommissionRequest,
  loadCommissionedSnapshotPlanContext,
  loadLatestSnapshotCommissionRequest,
  loadSnapshotCommissionPlanContext
} from "../src/snapshot-commission-control.js";
import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { sampleVamoEuPoiBatchYaml } from "../src/batch-plan-read-model.js";
import { persistBatchQueueSnapshot } from "../src/batch-queue-control.js";
import { sampleVamoEuPoiBatchQueueSnapshot } from "../src/batch-queue-read-model.js";
import { parseSnapshotCommissionRequestCreate } from "../src/snapshot-commission-request.js";
import { snapshotCommissionOperatorErrorForCode } from "../src/snapshot-commission-errors.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const confluendoBootstrapSql = readFileSync(
  "core/sql/control_bootstrap_confluendo.sql",
  "utf8"
);
import {
  resetDisposableTestDatabase,
  resolveDisposableTestDatabaseUrl
} from "./disposable-test-database.js";

const databaseUrl = resolveDisposableTestDatabaseUrl(process.env.INGESTION_TEST_DATABASE_URL);

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
const requestModule = readFileSync("core/src/snapshot-commission-request.ts", "utf8");

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
  geographies: {
    countries: [{ key: "italy" }, { key: "france" }]
  },
  categories: ["poi", "landmark"],
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
      },
      {
        providerCategoryIds: ["4bf58dd8d48988d181941735"],
        providerCategoryLabels: ["Museum"],
        consumerCategory: "landmark",
        precedence: 90
      }
    ]
  }
};

async function seedProjectAndPlan(
  client: Client,
  overrides: { planKey?: string; sourceKey?: string; status?: string } = {}
): Promise<{ planKey: string }> {
  const planKey = overrides.planKey ?? "vamo-eu-poi-sample";
  const sourceKey = overrides.sourceKey ?? "fsq-os-places-snapshot";
  const status = overrides.status ?? "active";

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
        $1::bigint, $2, $3, 'vamo-place-intelligence',
        'staging', 'dry_run', $4::jsonb, '{}'::jsonb, $5
      )
    `,
    [project.rows[0]!.id, planKey, sourceKey, JSON.stringify(planSpec), status]
  );
  return { planKey };
}

async function seedAutonomyPolicyBatchPlan(client: Client, batchPlanKey: string): Promise<void> {
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
      insert into ingestion_platform.ingestion_autonomy_policies (
        project_id, policy_key, source_key, target_key, target_environment, status,
        allowed_tiers, allowed_geographies, allowed_categories, allowed_transitions,
        max_units_per_cycle, max_rows_per_cycle, rolling_limits, policy_version, approved_by,
        approved_audit_id, approval_reason, ramp_mode, summary
      ) values (
        $1::bigint,
        'commission-smoke-policy',
        'fsq-os-places-snapshot',
        'vamo-place-intelligence',
        'staging',
        'active',
        '[]'::jsonb,
        '[]'::jsonb,
        '[]'::jsonb,
        '["schedule_dry_run"]'::jsonb,
        1,
        100,
        '{}'::jsonb,
        1,
        'owner@example.com',
        'audit-1',
        'commission smoke',
        'bootstrap',
        jsonb_build_object('batchPlanKey', $2::text)
      )
    `,
    [project.rows[0]!.id, batchPlanKey]
  );
}

async function seedQueueSnapshotForPlan(
  client: Client,
  planKey: string,
  now: string
): Promise<void> {
  const parsed = parseBatchPlanSpec(sampleVamoEuPoiBatchYaml());
  assert.equal(parsed.ok, true);
  if (!parsed.ok) {
    throw new Error("sample batch plan failed to parse");
  }
  const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
  await persistBatchQueueSnapshot({
    client,
    projectKey: "vamo",
    snapshot: {
      ...snapshot,
      planId: planKey,
      sourceKey: "fsq-os-places-snapshot"
    },
    spec: { ...parsed.spec, id: planKey, sourceKey: "fsq-os-places-snapshot" },
    now
  });
}

describe("snapshot commission control schema", () => {
  it("declares lease fields, active singleton index, and server-derived create function", () => {
    assert.match(controlSchemaSql, /claim_expires_at/);
    assert.match(controlSchemaSql, /attempt_count/);
    assert.match(controlSchemaSql, /ingestion_snapshot_commission_requests_one_active_per_plan_idx/);
    assert.match(controlSchemaSql, /v_plan_source_key is distinct from 'fsq-os-places-snapshot'/);
    assert.match(controlSchemaSql, /when unique_violation then/);
    assert.doesNotMatch(
      controlSchemaSql,
      /create_snapshot_commission_request\([\s\S]*p_source_key text/
    );
    assert.match(controlSchemaSql, /failure_telemetry jsonb not null default '\{\}'::jsonb/);
    assert.match(controlSchemaSql, /missing_failure_telemetry/);
    assert.match(controlSchemaSql, /jsonb_object_keys\(p_failure_telemetry\)/);
    assert.match(controlSchemaSql, /snapshot_commission\.failed/);
    assert.match(confluendoBootstrapSql, /grant select on ingestion_platform\.ingestion_snapshot_commission_requests/i);
    assert.match(confluendoBootstrapSql, /grant execute on function ingestion_platform\.create_snapshot_commission_request/i);
    assert.doesNotMatch(
      confluendoBootstrapSql,
      /grant execute on function ingestion_platform\.claim_snapshot_commission_request/i
    );
  });
});

describe("snapshot commission control DB smoke", () => {
  it(
    "allows app create/read, derives source from plan, and blocks direct state updates",
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
            countries: ["italy"],
            categories: ["poi"],
            maxRowsPerScope: 250,
            actor: { type: "operator", id: "dba@example.com" },
            auditReason: "Commission bounded snapshot release."
          });
          assert.equal(created.status, "requested");
          assert.equal(created.sourceKey, "fsq-os-places-snapshot");
          assert.ok(created.requestId);

          const latest = await loadLatestSnapshotCommissionRequest({
            client: app,
            projectKey: "vamo",
            planKey: "vamo-eu-poi-sample"
          });
          assert.equal(latest?.status, "requested");
          assert.equal(latest?.sourceKey, "fsq-os-places-snapshot");

          const ownedConnectionLatest = await loadLatestSnapshotCommissionRequest({
            connectionString: databaseUrl,
            projectKey: "vamo",
            planKey: "vamo-eu-poi-sample"
          });
          assert.equal(ownedConnectionLatest?.status, "requested");

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
        } finally {
          await app.end();
        }

        const leaseSeconds = 120;
        const claimStartedAt = Date.now();
        const claimed = await claimSnapshotCommissionRequest({
          client: owner,
          workerId: "commission-worker",
          workerRunKey: "run-smoke-1",
          leaseSeconds
        });
        assert.equal(claimed.ok, true);
        if (!claimed.ok) return;
        assert.equal(claimed.request.status, "running");
        assert.equal(claimed.idempotentReplay, false);
        assert.ok(claimed.request.claimExpiresAt);
        assert.equal(claimed.request.attemptCount, 1);
        const leaseDurationSeconds =
          (Date.parse(claimed.request.claimExpiresAt!) - claimStartedAt) / 1000;
        assert.ok(
          leaseDurationSeconds >= leaseSeconds - 5 && leaseDurationSeconds <= leaseSeconds + 5,
          `expected ~${leaseSeconds}s lease, observed ${leaseDurationSeconds}s`
        );
      } finally {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await resetDisposableTestDatabase(owner, databaseUrl!, { roles: ["confluendo_app"] });
        await owner.end();
      }
    }
  );

  it(
    "rejects archived plans, unsupported sources, and duplicate active requests",
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

        await seedProjectAndPlan(owner, {
          planKey: "archived-plan",
          status: "archived"
        });
        await seedProjectAndPlan(owner, {
          planKey: "sample-plan",
          sourceKey: "fsq-os-places-sample"
        });
        await seedProjectAndPlan(owner);

        await assert.rejects(
          () =>
            createSnapshotCommissionRequest({
              client: owner,
              projectKey: "vamo",
              planKey: "archived-plan",
              countries: ["italy"],
              categories: ["poi"],
              maxRowsPerScope: 250,
              actor: { type: "operator", id: "dba@example.com" },
              auditReason: "Should fail for archived plan."
            }),
          /plan_not_active/i
        );

        await assert.rejects(
          () =>
            createSnapshotCommissionRequest({
              client: owner,
              projectKey: "vamo",
              planKey: "sample-plan",
              countries: ["italy"],
              categories: ["poi"],
              maxRowsPerScope: 250,
              actor: { type: "operator", id: "dba@example.com" },
              auditReason: "Should fail for unsupported source."
            }),
          /unsupported_source_key/i
        );

        const first = await createSnapshotCommissionRequest({
          client: owner,
          projectKey: "vamo",
          planKey: "vamo-eu-poi-sample",
          countries: ["italy"],
          categories: ["poi"],
          maxRowsPerScope: 250,
          actor: { type: "operator", id: "dba@example.com" },
          auditReason: "First active request."
        });
        assert.ok(first.requestId);

        await assert.rejects(
          () =>
            createSnapshotCommissionRequest({
              client: owner,
              projectKey: "vamo",
              planKey: "vamo-eu-poi-sample",
              countries: ["italy"],
              categories: ["poi"],
              maxRowsPerScope: 250,
              actor: { type: "operator", id: "dba@example.com" },
              auditReason: "Duplicate active request."
            }),
          /commission_request_already_active/i
        );

        const activeCount = await owner.query<{ count: string }>(
          `
            select count(*)::text as count
            from ingestion_platform.ingestion_snapshot_commission_requests
            where status in ('requested', 'running', 'release_registered')
          `
        );
        assert.equal(activeCount.rows[0]?.count, "1");
      } finally {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await resetDisposableTestDatabase(owner, databaseUrl!, { roles: ["confluendo_app"] });
        await owner.end();
      }
    }
  );

  it(
    "reclaims expired leases and reconciles registered releases without duplicate acquisition",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const owner = new Client({ connectionString: databaseUrl });
      await owner.connect();

      try {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await owner.query(controlSchemaSql);
        await seedProjectAndPlan(owner);

        const created = await createSnapshotCommissionRequest({
          client: owner,
          projectKey: "vamo",
          planKey: "vamo-eu-poi-sample",
          countries: ["italy"],
          categories: ["poi"],
          maxRowsPerScope: 250,
          actor: { type: "operator", id: "dba@example.com" },
          auditReason: "Lease reclaim smoke."
        });

        const firstClaim = await claimSnapshotCommissionRequest({
          client: owner,
          workerId: "worker-a",
          workerRunKey: "run-expired",
          leaseSeconds: 120
        });
        assert.equal(firstClaim.ok, true);
        if (!firstClaim.ok) return;

        await owner.query(
          `
            update ingestion_platform.ingestion_snapshot_commission_requests
            set claim_expires_at = now() - interval '1 minute'
            where id = $1::bigint
          `,
          [created.requestId]
        );

        const reclaimed = await claimSnapshotCommissionRequest({
          client: owner,
          workerId: "worker-b",
          workerRunKey: "run-reclaim",
          leaseSeconds: 120
        });
        assert.equal(reclaimed.ok, true);
        if (!reclaimed.ok) return;
        assert.equal(reclaimed.leaseReclaimed, true);
        assert.equal(reclaimed.request.attemptCount, 2);

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
              'fsq_os_places-20260701-deadbeefcafe',
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
              '{"kind":"ingestion.snapshot_coverage_report","releaseId":"fsq_os_places-20260701-deadbeefcafe","derivedFromValidRowsOnly":true,"validRowCount":1,"invalidRowCount":0,"duplicateRowCount":0,"outOfScopeRowCount":0,"byCountry":{"italy":1},"byPoiType":{"poi":1}}'::jsonb,
              '{"valid":1,"invalid":0,"duplicate":0,"outOfScope":0}'::jsonb,
              jsonb_build_object('commissionRequestId', $1::text),
              now()
            from ingestion_platform.ingestion_projects p
            where p.project_key = 'vamo'
          `,
          [created.requestId]
        );

        const releaseId = await findSnapshotReleaseIdForCommissionRequest({
          client: owner,
          projectKey: "vamo",
          requestId: created.requestId
        });
        assert.equal(releaseId, "fsq_os_places-20260701-deadbeefcafe");

        await completeSnapshotCommissionRequest({
          client: owner,
          requestId: created.requestId,
          workerRunKey: "run-reclaim",
          status: "release_registered",
          registeredReleaseId: releaseId!
        });
        const finalized = await completeSnapshotCommissionRequest({
          client: owner,
          requestId: created.requestId,
          workerRunKey: "run-reclaim",
          status: "activation_pending",
          registeredReleaseId: releaseId!
        });
        assert.equal(finalized.status, "activation_pending");

        const activationBindings = await owner.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_snapshot_release_plan_bindings`
        );
        assert.equal(activationBindings.rows[0]?.count, "0");
      } finally {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await owner.end();
      }
    }
  );

  it(
    "loads server-side plan context for commissioning validation",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const owner = new Client({ connectionString: databaseUrl });
      await owner.connect();
      try {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await owner.query(controlSchemaSql);
        await seedProjectAndPlan(owner);

        const context = await loadSnapshotCommissionPlanContext({
          client: owner,
          projectKey: "vamo",
          planKey: "vamo-eu-poi-sample"
        });
        assert.ok(context);
        assert.equal(context?.sourceKey, "fsq-os-places-snapshot");
        assert.deepEqual(context?.allowedCountries, ["france", "italy"]);
        assert.deepEqual(context?.allowedCategories, ["landmark", "poi"]);
      } finally {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await owner.end();
      }
    }
  );

  it(
    "derives the commissioned plan from policy and queue context instead of request hints",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const owner = new Client({ connectionString: databaseUrl });
      await owner.connect();

      try {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await owner.query(controlSchemaSql);
        await seedProjectAndPlan(owner, { planKey: "forged-plan-key" });
        await seedAutonomyPolicyBatchPlan(owner, "vamo-eu-poi-sample");
        await seedQueueSnapshotForPlan(owner, "vamo-eu-poi-sample", "2026-07-02T12:00:00.000Z");

        const commissioned = await loadCommissionedSnapshotPlanContext({
          client: owner,
          projectKey: "vamo"
        });
        assert.equal(commissioned.ok, true);
        if (!commissioned.ok) return;
        assert.equal(commissioned.context.planKey, "vamo-eu-poi-sample");
        assert.equal(commissioned.planSource, "autonomy_policy");

        const forgedBody = parseSnapshotCommissionRequestCreate({
          projectKey: "vamo",
          planKey: "forged-plan-key",
          countries: ["italy"],
          categories: ["poi"],
          auditReason: "Forged plan hint must not change commissioning.",
          confirmedState: "request_commission"
        });
        assert.equal(forgedBody.ok, true);
        if (!forgedBody.ok) return;

        const created = await createSnapshotCommissionRequest({
          client: owner,
          projectKey: commissioned.context.projectKey,
          planKey: commissioned.context.planKey,
          countries: ["italy"],
          categories: ["poi"],
          maxRowsPerScope: 250,
          actor: { type: "operator", id: "dba@example.com" },
          auditReason: forgedBody.request.auditReason
        });
        assert.equal(created.sourceKey, "fsq-os-places-snapshot");

        const row = await owner.query<{ plan_key: string }>(
          `
            select bp.plan_key
            from ingestion_platform.ingestion_snapshot_commission_requests r
            join ingestion_platform.ingestion_batch_plans bp on bp.id = r.batch_plan_id
            where r.id = $1::bigint
          `,
          [created.requestId]
        );
        assert.equal(row.rows[0]?.plan_key, "vamo-eu-poi-sample");
        assert.notEqual(row.rows[0]?.plan_key, "forged-plan-key");
      } finally {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await owner.end();
      }
    }
  );

  it(
    "fails closed when autonomy policy and queue workflow disagree on the commissioned plan",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const owner = new Client({ connectionString: databaseUrl });
      await owner.connect();

      try {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await owner.query(controlSchemaSql);
        await seedAutonomyPolicyBatchPlan(owner, "policy-plan");
        await seedQueueSnapshotForPlan(owner, "policy-plan", "2026-07-02T12:00:00.000Z");
        await seedQueueSnapshotForPlan(owner, "queue-plan", "2026-07-02T13:00:00.000Z");

        const commissioned = await loadCommissionedSnapshotPlanContext({
          client: owner,
          projectKey: "vamo"
        });
        assert.deepEqual(commissioned, { ok: false, code: "commission_plan_context_mismatch" });
        assert.equal(
          snapshotCommissionOperatorErrorForCode("commission_plan_context_mismatch"),
          "The active autonomy policy and queue workflow disagree on the commissioned batch plan."
        );
      } finally {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await owner.end();
      }
    }
  );
});

describe("snapshot commission route artifact", () => {
  it("uses server-derived plan context and avoids provider, artifact, and consumer write paths", () => {
    const routeSource = readFileSync(commissionRoute, "utf8");
    assert.match(routeSource, /loadCommissionedSnapshotPlanContext/);
    assert.match(routeSource, /validateSnapshotCommissionScopeAgainstPlan/);
    assert.match(routeSource, /createSnapshotCommissionRequest/);
    assert.match(routeSource, /evaluateSnapshotCommissionRequestCreate/);
    assert.match(routeSource, /parseSnapshotCommissionRequestCreate/);
    assert.match(routeSource, /getActiveControlEnvironmentConfig/);
    assert.doesNotMatch(routeSource, /process\.env\.INGESTION_CONTROL_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /parsed\.request\.planKey/);
    assert.doesNotMatch(routeSource, /runFsqSnapshotAcquire/);
    assert.doesNotMatch(routeSource, /FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN/);
    assert.doesNotMatch(routeSource, /FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY/);
    assert.doesNotMatch(routeSource, /@duckdb\/node-api/);
    assert.doesNotMatch(routeSource, /CONFLUENDO_SNAPSHOT_ARTIFACT_S3_BUCKET/);
    assert.doesNotMatch(routeSource, /VAMO_STAGING_CANARY_APP_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /VAMO_PRODUCTION_INBOX_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /runSnapshotReleaseActivation/);
    assert.doesNotMatch(routeSource, /activateSnapshotRelease/);
    assert.doesNotMatch(routeSource, /parsed\.request\.sourceKey/);
  });

  it("does not expose execute acquisition from the browser control", () => {
    const controlSource = readFileSync(commissionControl, "utf8");
    assert.match(controlSource, /snapshot-commission\/request/);
    assert.doesNotMatch(controlSource, /runFsqSnapshotAcquire/);
    assert.doesNotMatch(controlSource, /FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN/);
    assert.doesNotMatch(controlSource, /FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY/);
    assert.doesNotMatch(controlSource, /@duckdb\/node-api/);
    assert.doesNotMatch(controlSource, /Execute acquisition/i);
    const postBodyBlock = controlSource.match(/body: JSON\.stringify\(\{[\s\S]*?\}\)/);
    assert.ok(postBodyBlock, "expected commissioning POST body");
    assert.doesNotMatch(postBodyBlock[0]!, /sourceKey/);
    assert.doesNotMatch(postBodyBlock[0]!, /planKey/);
    assert.match(controlSource, /trusted worker/i);
  });

  it("keeps commissioning parser free of provider adapter imports", () => {
    assert.doesNotMatch(requestModule, /adapters\/source/);
  });
});
