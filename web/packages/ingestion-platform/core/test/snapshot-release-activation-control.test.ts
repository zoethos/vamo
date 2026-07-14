import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { persistBatchQueueSnapshot } from "../src/batch-queue-control.js";
import { buildFullDataBoundBatchQueueSnapshot } from "../src/batch-supply-ready-proposal-binding.js";
import { readSnapshotSourceRowsFromSpec } from "../src/batch-snapshot-supply-preview.js";
import { registerSnapshotRelease } from "../src/snapshot-release-registry-control.js";
import { activateSnapshotRelease } from "../src/snapshot-release-activation-control.js";
import type { SourceAcquisitionReleaseRecord } from "../src/source-acquisition-contract.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const confluendoBootstrapSql = readFileSync(
  "core/sql/control_bootstrap_confluendo.sql",
  "utf8"
);
const fullDataYaml = readFileSync("fixtures/platform/ip18/vamo-eu-full-data-batch.yaml", "utf8");
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

describe("snapshot release activation control", () => {
  it("declares plan binding table and owner-controlled activation function", () => {
    assert.match(controlSchemaSql, /ingestion_snapshot_release_plan_bindings/);
    assert.match(controlSchemaSql, /create or replace function ingestion_platform\.activate_snapshot_release/);
    assert.match(controlSchemaSql, /ingestion_snapshot_release_plan_bindings_one_active_per_plan_idx/);
    assert.match(controlSchemaSql, /revoke all on function ingestion_platform\.activate_snapshot_release/);
    assert.match(
      confluendoBootstrapSql,
      /grant select on ingestion_platform\.ingestion_snapshot_release_plan_bindings to confluendo_app/i
    );
    assert.match(
      confluendoBootstrapSql,
      /grant execute on function ingestion_platform\.activate_snapshot_release/i
    );
    assert.doesNotMatch(
      confluendoBootstrapSql,
      /grant update on ingestion_platform\.ingestion_snapshot_release_plan_bindings/i
    );
  });

  it(
    "activates releases via security definer function and forbids direct app binding updates",
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

        const parsed = parseBatchPlanSpec(fullDataYaml);
        assert.equal(parsed.ok, true);
        if (!parsed.ok) {
          throw new Error("full-data plan failed to parse");
        }

        const rows = readSnapshotSourceRowsFromSpec(parsed.spec)!;
        const { snapshot } = buildFullDataBoundBatchQueueSnapshot({ spec: parsed.spec, rows });
        await persistBatchQueueSnapshot({
          client: owner,
          projectKey: "vamo",
          snapshot,
          spec: parsed.spec
        });

        const release = sampleRelease();
        const registered = await registerSnapshotRelease({
          client: owner,
          projectKey: "vamo",
          release,
          actor: { type: "operator", id: "dba@example.com" },
          auditReason: "Register validated FSQ snapshot release for activation smoke."
        });
        assert.equal(registered.status, "activation_ready");

        const activated = await activateSnapshotRelease({
          client: owner,
          projectKey: "vamo",
          planKey: "vamo-eu-full-data-v1",
          releaseId: release.releaseId,
          artifactBundleSha256: "d".repeat(64),
          actor: { type: "operator", id: "dba@example.com" },
          auditReason: "Activate verified snapshot release for full-data queue smoke."
        });
        assert.equal(activated.status, "activated");
        assert.ok(activated.bindingId);

        const activeBindings = await owner.query<{ count: string }>(
          `
            select count(*)::text as count
            from ingestion_platform.ingestion_snapshot_release_plan_bindings b
            join ingestion_platform.ingestion_batch_plans bp on bp.id = b.batch_plan_id
            where bp.plan_key = 'vamo-eu-full-data-v1'
              and b.status = 'active'
          `
        );
        assert.equal(activeBindings.rows[0]?.count, "1");

        const activationEvents = await owner.query<{
          eventType: string;
          severity: string;
          signal: string;
          message: string;
          releaseId: string;
          planKey: string;
        }>(
          `
            select
              event_type as "eventType",
              severity,
              signal,
              message,
              payload ->> 'releaseId' as "releaseId",
              payload ->> 'planKey' as "planKey"
            from ingestion_platform.ingestion_events
            where signal = 'snapshot.release.activated'
            order by id desc
            limit 1
          `
        );
        assert.deepEqual(activationEvents.rows[0], {
          eventType: "snapshot.release.activated",
          severity: "info",
          signal: "snapshot.release.activated",
          message: `Activated snapshot release ${release.releaseId} for batch plan vamo-eu-full-data-v1.`,
          releaseId: release.releaseId,
          planKey: "vamo-eu-full-data-v1"
        });

        const secondRelease = sampleRelease({
          releaseId: "fsq_os_places-20260701-secondrelease",
          outputSha256: "e".repeat(64),
          artifactKey:
            "fsq-os-places-snapshot/fsq_os_places-20260701-secondrelease/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        });
        await registerSnapshotRelease({
          client: owner,
          projectKey: "vamo",
          release: secondRelease,
          actor: { type: "operator", id: "dba@example.com" },
          auditReason: "Register second validated release for supersede smoke."
        });
        const secondActivated = await activateSnapshotRelease({
          client: owner,
          projectKey: "vamo",
          planKey: "vamo-eu-full-data-v1",
          releaseId: secondRelease.releaseId,
          artifactBundleSha256: "f".repeat(64),
          actor: { type: "operator", id: "dba@example.com" },
          auditReason: "Supersede prior active binding with a new release."
        });
        assert.equal(secondActivated.status, "activated");
        assert.notEqual(secondActivated.bindingId, activated.bindingId);

        const stillOneActive = await owner.query<{ count: string }>(
          `
            select count(*)::text as count
            from ingestion_platform.ingestion_snapshot_release_plan_bindings b
            join ingestion_platform.ingestion_batch_plans bp on bp.id = b.batch_plan_id
            where bp.plan_key = 'vamo-eu-full-data-v1'
              and b.status = 'active'
          `
        );
        assert.equal(stillOneActive.rows[0]?.count, "1");

        const app = new Client({
          connectionString: databaseUrl.replace(/\/\/[^@]+@/, "//confluendo_app:test@")
        });
        await app.connect();
        try {
          await assert.rejects(
            () =>
              app.query(
                `
                  update ingestion_platform.ingestion_snapshot_release_plan_bindings
                  set status = 'superseded'
                  where id = $1::bigint
                `,
                [activated.bindingId]
              ),
            /permission denied/i
          );

          const appActivated = await activateSnapshotRelease({
            client: app,
            projectKey: "vamo",
            planKey: "vamo-eu-full-data-v1",
            releaseId: secondRelease.releaseId,
            artifactBundleSha256: "f".repeat(64),
            actor: { type: "operator", id: "operator@example.com" },
            auditReason: "App role may execute activation via security definer."
          });
          assert.equal(appActivated.status, "activated");
        } finally {
          await app.end();
        }
      } finally {
        await owner.query("drop schema if exists ingestion_platform cascade");
        await owner.query("drop role if exists confluendo_app");
        await owner.end();
      }
    }
  );
});

function sampleRelease(overrides: Partial<SourceAcquisitionReleaseRecord> = {}): SourceAcquisitionReleaseRecord {
  return {
    kind: "ingestion.source_acquisition_release",
    releaseId: "fsq_os_places-20260701-deadbeefcafe",
    sourceKey: "fsq-os-places-snapshot",
    sourceProvider: "fsq_os_places",
    acquiredAt: "2026-07-01T12:00:00.000Z",
    provenanceUrl: "https://places.foursquare.com/products/open-source-places",
    inputSha256: "a".repeat(64),
    outputSha256: "b".repeat(64),
    sourceAttribution: "FSQ Open Source Places",
    licenseIdentifier: "FSQ-OS-Places",
    retentionStatement: "Retain until superseded.",
    intendedConsumer: "vamo",
    intendedTarget: "vamo-place-intelligence",
    artifactKey: "fsq-os-places-snapshot/fsq_os_places-20260701-deadbeefcafe/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    artifactUri: "file:///tmp/confluendo-snapshot-artifacts/fsq-os-places-snapshot",
    status: "activation_ready",
    coverage: {
      kind: "ingestion.snapshot_coverage_report",
      releaseId: "fsq_os_places-20260701-deadbeefcafe",
      derivedFromValidRowsOnly: true,
      validRowCount: 2,
      invalidRowCount: 0,
      duplicateRowCount: 0,
      outOfScopeRowCount: 0,
      byCountry: { italy: 1, france: 1 },
      byPoiType: { poi: 1, landmark: 1 }
    },
    rowCounts: {
      valid: 2,
      invalid: 0,
      duplicate: 0,
      outOfScope: 0
    },
    ...overrides
  };
}
