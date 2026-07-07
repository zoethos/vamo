import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import type { AdminPrincipal } from "../src/admin-auth.js";
import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { sampleVamoEuPoiBatchYaml } from "../src/batch-plan-read-model.js";
import {
  buildBatchQueueSnapshotFromItems,
  sampleVamoEuPoiBatchQueueSnapshot
} from "../src/batch-queue-read-model.js";
import { approveBatchProductionPackageWave } from "../src/batch-production-package-wave-control.js";
import {
  VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
  evaluateProductionPackageWaveApproval
} from "../src/batch-production-package-wave-policy.js";
import { loadBatchQueueSnapshot } from "../src/batch-queue-control-read.js";
import { persistBatchQueueSnapshot } from "../src/batch-queue-control.js";
import { CONTROL_TABLES } from "../src/control-models.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const confluendoBootstrapSql = readFileSync(
  "core/sql/control_bootstrap_confluendo.sql",
  "utf8"
);
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;
const NOW = "2026-07-07T10:00:00.000Z";

describe("batch production package-wave approval control", () => {
  it(
    "approves wave, idempotent replay, and reloads package-wave read model",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.query(controlSchemaSql);
        assert.equal(CONTROL_TABLES.length, 27);

        await client.query(
          `
            insert into ingestion_platform.ingestion_projects (project_key, display_name)
            values ('vamo', 'Vamo')
          `
        );

        const parsed = parseBatchPlanSpec(sampleVamoEuPoiBatchYaml());
        assert.equal(parsed.ok, true);
        if (!parsed.ok) throw new Error("sample yaml failed to parse");

        const stagingUnitKey = "vamo-place-intelligence:paris-france:landmark";
        const snapshot = buildBatchQueueSnapshotFromItems({
          planId: "vamo-eu-poi-sample",
          projectKey: "vamo",
          targetKey: "vamo-place-intelligence",
          targetEnvironment: "staging",
          sourceKey: "fsq-os-places-sample",
          safetyMode: "dry_run",
          items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) =>
            item.unitKey === stagingUnitKey
              ? {
                  ...item,
                  status: "staging_canary_succeeded" as const,
                  dryRunReport: {
                    wroteToTarget: false as const,
                    rowsProcessed: 2,
                    insertCount: 2,
                    updateCount: 0,
                    noOpCount: 0,
                    executionKey: "dry-run:smoke"
                  }
                }
              : item
          )
        });

        await persistBatchQueueSnapshot({
          client,
          projectKey: "vamo",
          snapshot,
          spec: parsed.spec
        });

        const loaded = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
        assert.ok(loaded);
        assert.equal(loaded.latestProductionPackageWave, null);

        const decision = evaluateProductionPackageWaveApproval({
          projectKey: "vamo",
          snapshot: loaded,
          principal: adminPrincipal(),
          targetKey: "vamo-place-intelligence",
          targetEnvironment: "production",
          schemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
          maxUnits: 1,
          maxRows: 10,
          maxPackages: 1,
          auditReason: "Approve first production package wave smoke.",
          stagingEvidenceByUnitKey: {
            [stagingUnitKey]: {
              status: "succeeded",
              shipmentKey: "staging:smoke",
              shipmentId: "99"
            }
          },
          now: NOW
        });
        assert.equal(decision.ok, true, decision.ok ? "" : JSON.stringify((decision as { blocks?: unknown }).blocks));
        if (!decision.ok) throw new Error("approval policy should accept");

        const first = await approveBatchProductionPackageWave({
          client,
          projectKey: "vamo",
          plan: decision.plan,
          actor: { type: "operator", id: "admin-smoke" },
          now: NOW
        });
        assert.equal(first.idempotentReplay, false);
        assert.equal(first.unitKeys.length, 1);
        assert.ok(first.auditId);
        assert.match(first.waveKey, new RegExp(`:wave:${first.auditId}:unit:`));

        const waveRow = await client.query<{ approvalAuditId: string | null; waveKey: string }>(
          `
            select approval_audit_id as "approvalAuditId", wave_key as "waveKey"
            from ingestion_platform.ingestion_batch_production_package_waves
            where id = $1::bigint
          `,
          [first.waveId]
        );
        assert.equal(waveRow.rows[0]?.approvalAuditId, first.auditId);
        assert.equal(waveRow.rows[0]?.waveKey, first.waveKey);

        const replay = await approveBatchProductionPackageWave({
          client,
          projectKey: "vamo",
          plan: decision.plan,
          actor: { type: "operator", id: "admin-smoke" },
          now: NOW
        });
        assert.equal(replay.idempotentReplay, true);
        assert.equal(replay.waveId, first.waveId);
        assert.equal(replay.auditId, first.auditId);
        assert.equal(replay.waveKey, first.waveKey);

        const waveCount = await client.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_batch_production_package_waves`
        );
        assert.equal(waveCount.rows[0]?.count, "1");

        const after = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
        assert.ok(after?.latestProductionPackageWave);
        assert.equal(after.latestProductionPackageWave?.status, "approved");
        assert.equal(after.latestProductionPackageWave?.schemaContract, VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT);
        assert.equal(after.latestProductionPackageWave?.targetEnvironment, "production");
        assert.ok(after.latestProductionPackageWave?.approvalExpiresAt);
        assert.equal(after.progress.productionPackage.approved, 1);

        const approvedUnit = after.items.find((item) => item.unitKey === first.unitKeys[0]);
        assert.equal(approvedUnit?.status, "production_package_approved");
      } finally {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.end();
      }
    }
  );

  it(
    "grants confluendo_app insert/update on package-wave tables and forbids delete",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.query("drop role if exists confluendo_app");
        await client.query(controlSchemaSql);
        await client.query("create role confluendo_app login password 'test'");
        await client.query(confluendoBootstrapSql);

        await client.query(
          `
            insert into ingestion_platform.ingestion_projects (project_key, display_name)
            values ('grant-smoke-vamo', 'Grant Smoke')
          `
        );
        const plan = await client.query<{ id: string }>(
          `
            insert into ingestion_platform.ingestion_batch_plans (
              project_id, plan_key, source_key, target_key, target_environment, safety_mode, spec, plan_summary, status
            )
            select id, 'plan-smoke', 'src', 'vamo-place-intelligence', 'staging', 'dry_run', '{}'::jsonb, '{}'::jsonb, 'active'
            from ingestion_platform.ingestion_projects
            where project_key = 'grant-smoke-vamo'
            returning id::text as id
          `
        );
        const batchPlanId = plan.rows[0]!.id;

        const app = new Client({
          connectionString: databaseUrl.replace(/\/\/[^@]+@/, "//confluendo_app:test@")
        });
        await app.connect();

        const wave = await app.query<{ id: string }>(
          `
            insert into ingestion_platform.ingestion_batch_production_package_waves (
              project_id, batch_plan_id, wave_key, target_key, target_environment, schema_contract,
              max_units, max_rows, max_packages, approval_reason, approved_by, approved_at,
              approval_expires_at, actor_type, actor_id, status
            )
            select p.id, $1::bigint, 'wave-smoke', 'vamo-place-intelligence', 'production',
              'vamo-place-intelligence@1', 1, 2, 1, 'smoke', '{}'::jsonb, now(), now() + interval '15 minutes',
              'operator', 'smoke', 'approved'
            from ingestion_platform.ingestion_projects p
            where p.project_key = 'grant-smoke-vamo'
            returning id::text as id
          `,
          [batchPlanId]
        );

        await assert.rejects(
          () =>
            app.query(
              `delete from ingestion_platform.ingestion_batch_production_package_waves where wave_key = 'wave-smoke'`
            ),
          /permission denied/i
        );

        await app.end();
      } finally {
        await client.query("drop owned by confluendo_app");
        await client.query("drop role if exists confluendo_app");
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.end();
      }
    }
  );
});

function adminPrincipal(): AdminPrincipal {
  return {
    provider: "test",
    userId: "admin-smoke",
    email: "admin@vamo.test",
    role: "admin",
    scopes: ["vamo"],
    assuranceLevel: "aal2",
    mfaRequired: true,
    hasVerifiedMfaFactor: true,
    stepUpSatisfiedAt: "2026-07-07T09:58:00.000Z"
  };
}
