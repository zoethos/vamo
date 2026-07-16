import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { Client } from "pg";

import {
  PLAN_CONTRACT_REFRESH_CONFIRMATION_STATE,
  evaluateBatchPlanContractRefresh,
  parseBatchPlanContractRefreshRequest,
  presentBatchPlanContractRefreshCard,
  resolvePublishedPlanSourceTaxonomyContract
} from "../src/batch-plan-contract-refresh.js";
import {
  loadBatchPlanSourceTaxonomyState,
  refreshBatchPlanSourceTaxonomy
} from "../src/batch-plan-contract-refresh-control.js";
import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const confluendoBootstrapSql = readFileSync(
  "core/sql/control_bootstrap_confluendo.sql",
  "utf8"
);
const fullDataPlanYaml = readFileSync(
  "fixtures/platform/ip18/vamo-eu-full-data-batch.yaml",
  "utf8"
);
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;
const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const refreshRoute = join(
  webRoot,
  "apps/confluendo-console/app/api/admin/ingestion/batch-plan/source-taxonomy/refresh/route.ts"
);

describe("batch plan contract refresh", () => {
  it("pins the published Vamo source taxonomy to the checked-in full-data plan", () => {
    const parsed = parseBatchPlanSpec(fullDataPlanYaml);
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;

    const published = resolvePublishedPlanSourceTaxonomyContract({
      projectKey: "vamo",
      planKey: "vamo-eu-full-data-v1",
      sourceKey: "fsq-os-places-snapshot"
    });
    assert.ok(published);
    assert.deepEqual(published.sourceTaxonomy, parsed.spec.sourceTaxonomy);
  });

  it("parses only operator intent and rejects client taxonomy or plan hints", () => {
    const parsed = parseBatchPlanContractRefreshRequest({
      projectKey: "vamo",
      planKey: "forged-plan-key",
      sourceTaxonomy: { provider: "forged" },
      auditReason: "Add the published provider mapping without reseeding history.",
      confirmedState: PLAN_CONTRACT_REFRESH_CONFIRMATION_STATE
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.deepEqual(parsed.request, {
      projectKey: "vamo",
      auditReason: "Add the published provider mapping without reseeding history.",
      confirmedState: PLAN_CONTRACT_REFRESH_CONFIRMATION_STATE
    });
  });

  it("requires fresh admin MFA and never replaces an existing mapping", () => {
    const published = resolvePublishedPlanSourceTaxonomyContract({
      projectKey: "vamo",
      planKey: "vamo-eu-full-data-v1",
      sourceKey: "fsq-os-places-snapshot"
    });
    assert.ok(published);

    const missingStepUp = evaluateBatchPlanContractRefresh({
      actor: {
        type: "operator",
        id: "supabase:user-id",
        role: "admin",
        assuranceLevel: "aal2",
        stepUpFresh: false
      },
      auditReason: "Add source taxonomy.",
      currentSourceTaxonomy: undefined,
      publishedContract: published
    });
    assert.equal(missingStepUp.ok, false);
    if (!missingStepUp.ok) {
      assert.ok(missingStepUp.blocks.some((block) => block.code === "fresh_step_up_required"));
    }

    const alreadyConfigured = evaluateBatchPlanContractRefresh({
      actor: {
        type: "operator",
        id: "supabase:user-id",
        role: "admin",
        assuranceLevel: "aal2",
        stepUpFresh: true
      },
      auditReason: "Try to replace an existing source mapping.",
      currentSourceTaxonomy: published.sourceTaxonomy,
      publishedContract: published
    });
    assert.equal(alreadyConfigured.ok, false);
    if (!alreadyConfigured.ok) {
      assert.ok(alreadyConfigured.blocks.some((block) => block.code === "mapping_already_configured"));
    }

    const malformedMapping = evaluateBatchPlanContractRefresh({
      actor: {
        type: "operator",
        id: "supabase:user-id",
        role: "admin",
        assuranceLevel: "aal2",
        stepUpFresh: true
      },
      auditReason: "Try to replace malformed source mapping.",
      currentSourceTaxonomy: { provider: "fsq_os_places" },
      publishedContract: published
    });
    assert.equal(malformedMapping.ok, false);
    if (!malformedMapping.ok) {
      assert.ok(malformedMapping.blocks.some((block) => block.code === "mapping_already_configured"));
    }
  });

  it("presents a bounded metadata-only action and a protected configured state", () => {
    const missing = presentBatchPlanContractRefreshCard({
      projectKey: "vamo",
      planKey: "vamo-eu-full-data-v1",
      sourceKey: "fsq-os-places-snapshot",
      liveControlPlane: true
    });
    assert.equal(missing.canRefresh, true);
    assert.equal(missing.statusLabel, "Mapping required");

    const published = resolvePublishedPlanSourceTaxonomyContract({
      projectKey: "vamo",
      planKey: "vamo-eu-full-data-v1",
      sourceKey: "fsq-os-places-snapshot"
    });
    assert.ok(published);
    const configured = presentBatchPlanContractRefreshCard({
      projectKey: "vamo",
      planKey: "vamo-eu-full-data-v1",
      sourceKey: "fsq-os-places-snapshot",
      currentSourceTaxonomy: published.sourceTaxonomy,
      liveControlPlane: true
    });
    assert.equal(configured.canRefresh, false);
    assert.equal(configured.statusLabel, "Configured");

    const malformed = presentBatchPlanContractRefreshCard({
      projectKey: "vamo",
      planKey: "vamo-eu-full-data-v1",
      sourceKey: "fsq-os-places-snapshot",
      currentSourceTaxonomy: { provider: "fsq_os_places" },
      liveControlPlane: true
    });
    assert.equal(malformed.canRefresh, false);
    assert.equal(malformed.statusLabel, "Mapping needs review");
  });

  it("keeps the browser route server-pinned and away from provider or queue mutation paths", () => {
    const routeSource = readFileSync(refreshRoute, "utf8");
    assert.match(routeSource, /loadCommissionedSnapshotPlanContext/);
    assert.match(routeSource, /resolvePublishedPlanSourceTaxonomyContract/);
    assert.match(routeSource, /refreshBatchPlanSourceTaxonomy/);
    assert.doesNotMatch(routeSource, /FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN/);
    assert.doesNotMatch(routeSource, /adapters\/source/);
    assert.doesNotMatch(routeSource, /persistBatchQueueSnapshot/);
    assert.doesNotMatch(routeSource, /update ingestion_platform\.ingestion_batch_queue_items/i);
  });

  it(
    "allows the app function path while preserving queue evidence and denying direct plan updates",
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
        const plan = await owner.query<{ id: string }>(
          `
            insert into ingestion_platform.ingestion_batch_plans (
              project_id, plan_key, source_key, target_key, target_environment, safety_mode, spec, plan_summary, status
            ) select
              id, 'vamo-eu-full-data-v1', 'fsq-os-places-snapshot', 'vamo-place-intelligence', 'staging', 'dry_run',
              '{"id":"vamo-eu-full-data-v1","sourceKey":"fsq-os-places-snapshot"}'::jsonb,
              '{"preserve":"summary"}'::jsonb, 'active'
            from ingestion_platform.ingestion_projects
            where project_key = 'vamo'
            returning id::text as id
          `
        );
        const planId = plan.rows[0]?.id;
        assert.ok(planId);
        await owner.query(
          `
            insert into ingestion_platform.ingestion_batch_queue_items (
              batch_plan_id, unit_key, country_code, geography_key, geography_label, geography_kind,
              category, source_key, target_key, target_environment, status, priority, run_order, blockers, proposal, run_report
            ) values (
              $1::bigint, 'vamo-place-intelligence:rome-italy:poi', 'IT', 'rome-italy', 'Rome, Italy', 'city',
              'poi', 'fsq-os-places-snapshot', 'vamo-place-intelligence', 'staging', 'applied', 5, 1, '[]'::jsonb,
              '{"scope":{"rowLimit":2}}'::jsonb, '{"status":"dry_run_succeeded","evidence":"preserve"}'::jsonb
            )
          `,
          [planId]
        );

        const app = new Client({
          connectionString: databaseUrl.replace(/\/\/[^@]+@/, "//confluendo_app:test@")
        });
        await app.connect();
        try {
          await assert.rejects(
            () =>
              app.query(
                "update ingestion_platform.ingestion_batch_plans set spec = '{}'::jsonb where id = $1::bigint",
                [planId]
              ),
            /permission denied/i
          );

          const before = await loadBatchPlanSourceTaxonomyState({
            client: app,
            projectKey: "vamo",
            planKey: "vamo-eu-full-data-v1"
          });
          assert.equal(before?.sourceTaxonomy, null);

          const published = resolvePublishedPlanSourceTaxonomyContract({
            projectKey: "vamo",
            planKey: "vamo-eu-full-data-v1",
            sourceKey: "fsq-os-places-snapshot"
          });
          assert.ok(published);
          const refreshed = await refreshBatchPlanSourceTaxonomy({
            client: app,
            projectKey: "vamo",
            planKey: "vamo-eu-full-data-v1",
            sourceKey: "fsq-os-places-snapshot",
            sourceTaxonomy: published.sourceTaxonomy,
            actor: { type: "operator", id: "supabase:admin" },
            auditReason: "Add the published source mapping without reseeding history."
          });
          assert.equal(refreshed.changed, true);
          assert.ok(refreshed.auditId);

          const replay = await refreshBatchPlanSourceTaxonomy({
            client: app,
            projectKey: "vamo",
            planKey: "vamo-eu-full-data-v1",
            sourceKey: "fsq-os-places-snapshot",
            sourceTaxonomy: published.sourceTaxonomy,
            actor: { type: "operator", id: "supabase:admin" },
            auditReason: "Repeat should not replace an existing mapping."
          });
          assert.equal(replay.changed, false);
          assert.equal(replay.auditId, undefined);
        } finally {
          await app.end();
        }

        const evidence = await owner.query<{
          spec: { sourceTaxonomy: unknown };
          planSummary: unknown;
          status: string;
          proposal: unknown;
          runReport: unknown;
          queueStatus: string;
          audits: string[];
          events: string[];
        }>(
          `
            select
              bp.spec as spec,
              bp.plan_summary as "planSummary",
              bp.status,
              qi.proposal as proposal,
              qi.run_report as "runReport",
              qi.status as "queueStatus",
              array(select action from ingestion_platform.ingestion_audit_log order by id) as audits,
              array(select event_type from ingestion_platform.ingestion_events order by id) as events
            from ingestion_platform.ingestion_batch_plans bp
            join ingestion_platform.ingestion_batch_queue_items qi on qi.batch_plan_id = bp.id
            where bp.id = $1::bigint
          `,
          [planId]
        );
        const row = evidence.rows[0];
        assert.ok(row);
        assert.deepEqual(row.planSummary, { preserve: "summary" });
        assert.equal(row.status, "active");
        assert.equal(row.queueStatus, "applied");
        assert.deepEqual(row.proposal, { scope: { rowLimit: 2 } });
        assert.deepEqual(row.runReport, { status: "dry_run_succeeded", evidence: "preserve" });
        assert.ok(row.spec.sourceTaxonomy);
        assert.deepEqual(row.audits, ["refresh_batch_plan_source_taxonomy"]);
        assert.deepEqual(row.events, ["batch_plan.source_taxonomy_refreshed"]);
      } finally {
        await owner.query("drop schema if exists ingestion_platform cascade").catch(() => undefined);
        await owner.query("drop role if exists confluendo_app").catch(() => undefined);
        await owner.end();
      }
    }
  );
});
