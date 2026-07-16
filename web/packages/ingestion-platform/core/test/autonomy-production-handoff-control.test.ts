import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import { setAutonomyProductionHandoff } from "../src/autonomy-production-handoff-control.js";

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

describe("autonomy production handoff control", () => {
  it(
    "allows audited function changes but forbids direct policy updates by app role",
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
              production_inbox_handoff_policy,
              approved_by,
              approved_audit_id,
              approval_reason,
              summary
            )
            select
              id,
              'handoff-smoke',
              'fsq-os-places-snapshot',
              'vamo-place-intelligence',
              'staging',
              'active',
              '["sample_dry_run"]'::jsonb,
              '["schedule_dry_run","execute_dry_run","approve_staging_wave"]'::jsonb,
              100,
              25000,
              '{"maxCyclesPerDay":100,"maxUnitsPerDay":200,"maxRowsPerDay":2000}'::jsonb,
              'volume_ramp',
              4,
              '{"requiresIp18_6":true}'::jsonb,
              'owner@example.com',
              'owner-audit',
              'owner ceiling smoke',
              '{"rampMode":"volume_ramp"}'::jsonb
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
                `
                  update ingestion_platform.ingestion_autonomy_policies
                  set production_inbox_handoff_policy = '{"enabled":true}'::jsonb
                  where policy_key = 'handoff-smoke'
                `
              ),
            /permission denied/i
          );

          const enabled = await setAutonomyProductionHandoff({
            client: app,
            projectKey: "vamo",
            policyKey: "handoff-smoke",
            expectedEnabled: false,
            requestedEnabled: true,
            actor: { type: "operator", id: "dba@example.com" },
            auditReason: "Enable production package handoff after live proof."
          });

          assert.equal(enabled.fromEnabled, false);
          assert.equal(enabled.toEnabled, true);
          assert.equal(enabled.policyVersion, 5);
          assert.equal(enabled.productionInboxHandoffPolicy.enabled, true);
          assert.equal(enabled.productionInboxHandoffPolicy.requiresIp18_6, false);
          assert.equal(enabled.productionInboxHandoffPolicy.consumerApplyEnabled, false);
          assert.ok(enabled.allowedTransitions.includes("approve_production_package_wave"));
          assert.ok(enabled.allowedTransitions.includes("deliver_production_package_wave"));

          await assert.rejects(
            () =>
              setAutonomyProductionHandoff({
                client: app,
                projectKey: "vamo",
                policyKey: "handoff-smoke",
                expectedEnabled: false,
                requestedEnabled: true,
                actor: { type: "operator", id: "dba@example.com" },
                auditReason: "Stale expectation."
              }),
            /production_handoff_conflict/
          );

          const disabled = await setAutonomyProductionHandoff({
            client: app,
            projectKey: "vamo",
            policyKey: "handoff-smoke",
            expectedEnabled: true,
            requestedEnabled: false,
            actor: { type: "operator", id: "dba@example.com" },
            auditReason: "Disable production handoff during review."
          });

          assert.equal(disabled.fromEnabled, true);
          assert.equal(disabled.toEnabled, false);
          assert.equal(disabled.policyVersion, 6);
          assert.equal(disabled.productionInboxHandoffPolicy.enabled, false);
          assert.equal(disabled.productionInboxHandoffPolicy.consumerApplyEnabled, false);
          assert.ok(!disabled.allowedTransitions.includes("approve_production_package_wave"));
          assert.ok(!disabled.allowedTransitions.includes("deliver_production_package_wave"));
        } finally {
          await app.end();
        }

        const evidence = await owner.query<{
          enabled: boolean;
          requiresIp18_6: boolean;
          consumerApplyEnabled: boolean;
          allowedTransitions: string[];
          actions: string[];
          events: string[];
        }>(
          `
            select
              (ap.production_inbox_handoff_policy->>'enabled')::boolean as "enabled",
              (ap.production_inbox_handoff_policy->>'requiresIp18_6')::boolean as "requiresIp18_6",
              (ap.production_inbox_handoff_policy->>'consumerApplyEnabled')::boolean as "consumerApplyEnabled",
              array(
                select value
                from jsonb_array_elements_text(ap.allowed_transitions) as transition(value)
                order by value
              ) as "allowedTransitions",
              array_agg(distinct audit.action order by audit.action) as "actions",
              array_agg(distinct events.event_type order by events.event_type) as "events"
            from ingestion_platform.ingestion_autonomy_policies ap
            join ingestion_platform.ingestion_audit_log audit
              on audit.target_type = 'autonomy_policy'
             and audit.target_id = ap.id::text
            join ingestion_platform.ingestion_events events
              on events.project_id = ap.project_id
             and events.signal = 'autonomy_production_handoff'
            where ap.policy_key = 'handoff-smoke'
            group by ap.id
          `
        );

        assert.equal(evidence.rows[0]?.enabled, false);
        assert.equal(evidence.rows[0]?.requiresIp18_6, false);
        assert.equal(evidence.rows[0]?.consumerApplyEnabled, false);
        assert.ok(!evidence.rows[0]?.allowedTransitions.includes("approve_production_package_wave"));
        assert.deepEqual(evidence.rows[0]?.actions, [
          "disable_production_inbox_handoff",
          "enable_production_inbox_handoff"
        ]);
        assert.deepEqual(evidence.rows[0]?.events, [
          "autonomy.production_handoff.disabled",
          "autonomy.production_handoff.enabled"
        ]);
      } finally {
        await resetDisposableTestDatabase(owner, databaseUrl!, { ownedRoles: ["confluendo_app"] });
        await resetDisposableTestDatabase(owner, databaseUrl!, { roles: ["confluendo_app"] });
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await owner.end();
      }
    }
  );
});
