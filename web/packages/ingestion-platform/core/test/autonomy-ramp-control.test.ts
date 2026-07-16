import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import { promoteAutonomyRamp } from "../src/autonomy-ramp-control.js";

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

describe("autonomy ramp control", () => {
  it(
    "allows audited function promotion but forbids direct policy updates by app role",
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

        const policy = await owner.query<{ id: string }>(
          `
            insert into ingestion_platform.ingestion_autonomy_policies (
              project_id,
              policy_key,
              source_key,
              target_key,
              target_environment,
              status,
              allowed_tiers,
              allowed_transitions,
              max_units_per_cycle,
              max_rows_per_cycle,
              rolling_limits,
              ramp_mode,
              policy_version,
              approved_by,
              approved_audit_id,
              approval_reason,
              summary
            )
            select
              id,
              'ramp-smoke',
              'fsq-os-places-sample',
              'vamo-place-intelligence',
              'staging',
              'active',
              '["sample_dry_run"]'::jsonb,
              '["execute_dry_run"]'::jsonb,
              100,
              25000,
              '{"maxCyclesPerDay":999,"maxUnitsPerDay":999,"maxRowsPerDay":999}'::jsonb,
              'bootstrap',
              1,
              'owner@example.com',
              'owner-audit',
              'owner ceiling smoke',
              '{"rampMode":"bootstrap"}'::jsonb
            from ingestion_platform.ingestion_projects
            where project_key = 'vamo'
            returning id::text as id
          `
        );
        assert.ok(policy.rows[0]?.id);

        const app = new Client({
          connectionString: databaseUrl.replace(/\/\/[^@]+@/, "//confluendo_app:test@")
        });
        await app.connect();

        try {
          await assert.rejects(
            () =>
              app.query(
                `update ingestion_platform.ingestion_autonomy_policies set ramp_mode = 'volume_ramp' where policy_key = 'ramp-smoke'`
              ),
            /permission denied/i
          );

          const promoted = await promoteAutonomyRamp({
            client: app,
            projectKey: "vamo",
            policyKey: "ramp-smoke",
            expectedCurrentMode: "bootstrap",
            requestedMode: "staging_ramp",
            actor: { type: "operator", id: "dba@example.com" },
            auditReason: "Promote bootstrap proof to staging ramp."
          });
          assert.equal(promoted.fromMode, "bootstrap");
          assert.equal(promoted.toMode, "staging_ramp");
          assert.ok(promoted.auditId);

          await assert.rejects(
            () =>
              promoteAutonomyRamp({
                client: app,
                projectKey: "vamo",
                policyKey: "ramp-smoke",
                expectedCurrentMode: "bootstrap",
                requestedMode: "staging_ramp",
                actor: { type: "operator", id: "dba@example.com" },
                auditReason: "Stale expectation."
              }),
            /ramp_mode_conflict/
          );
        } finally {
          await app.end();
        }

        const evidence = await owner.query<{
          rampMode: string;
          auditAction: string;
          eventType: string;
        }>(
          `
            select
              ap.ramp_mode as "rampMode",
              audit.action as "auditAction",
              events.event_type as "eventType"
            from ingestion_platform.ingestion_autonomy_policies ap
            join ingestion_platform.ingestion_audit_log audit
              on audit.target_type = 'autonomy_policy'
             and audit.target_id = ap.id::text
            join ingestion_platform.ingestion_events events
              on events.project_id = ap.project_id
             and events.signal = 'autonomy_ramp'
            where ap.policy_key = 'ramp-smoke'
          `
        );
        assert.equal(evidence.rows[0]?.rampMode, "staging_ramp");
        assert.equal(evidence.rows[0]?.auditAction, "promote_autonomy_ramp");
        assert.equal(evidence.rows[0]?.eventType, "autonomy.ramp.promoted");
      } finally {
        await resetDisposableTestDatabase(owner, databaseUrl!, { ownedRoles: ["confluendo_app"] });
        await resetDisposableTestDatabase(owner, databaseUrl!, { roles: ["confluendo_app"] });
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await owner.end();
      }
    }
  );
});
