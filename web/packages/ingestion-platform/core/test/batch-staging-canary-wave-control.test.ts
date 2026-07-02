import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { sampleVamoEuPoiBatchYaml } from "../src/batch-plan-read-model.js";
import {
  buildBatchQueueSnapshotFromItems,
  sampleVamoEuPoiBatchQueueSnapshot
} from "../src/batch-queue-read-model.js";
import { evaluateBatchStagingCanaryWaveApproval } from "../src/batch-staging-canary-wave-policy.js";
import { approveBatchStagingCanaryWave } from "../src/batch-staging-canary-wave-control.js";
import { loadBatchQueueSnapshot } from "../src/batch-queue-control-read.js";
import { persistBatchQueueSnapshot } from "../src/batch-queue-control.js";
import { executeBatchDryRun } from "../src/batch-dry-run-execution.js";
import { evaluateBatchDryRunExecution } from "../src/batch-dry-run-execution-policy.js";
import { scheduleBatchDryRun } from "../src/batch-queue-mutations.js";
import type { AdminPrincipal } from "../src/admin-auth.js";
import { CONTROL_TABLES } from "../src/control-models.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

const NOW = "2026-07-02T14:00:00.000Z";

describe("batch staging-canary wave approval control", () => {
  it(
    "approves wave, idempotent replay, and blocks invalid queue statuses",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.query(controlSchemaSql);
        assert.equal(CONTROL_TABLES.length, 23);

        await client.query(
          `
            insert into ingestion_platform.ingestion_projects (project_key, display_name)
            values ('vamo', 'Vamo')
          `
        );

        const parsed = parseBatchPlanSpec(sampleVamoEuPoiBatchYaml());
        assert.equal(parsed.ok, true);
        if (!parsed.ok) {
          throw new Error("sample yaml failed to parse");
        }

        const scheduledSnapshot = buildBatchQueueSnapshotFromItems({
          planId: "vamo-eu-poi-sample",
          projectKey: "vamo",
          targetKey: "vamo-place-intelligence",
          targetEnvironment: "staging",
          sourceKey: "fsq-os-places-sample",
          safetyMode: "dry_run",
          items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) => ({
            ...item,
            status: "ready_for_dry_run"
          }))
        });

        await persistBatchQueueSnapshot({
          client,
          projectKey: "vamo",
          snapshot: scheduledSnapshot,
          spec: parsed.spec
        });

        await scheduleBatchDryRun({
          client,
          projectKey: "vamo",
          planId: "vamo-eu-poi-sample",
          targetKey: "vamo-place-intelligence",
          actor: { type: "operator", id: "operator-smoke" },
          reason: "Schedule for wave approval smoke",
          payload: {}
        });

        const loaded = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
        assert.ok(loaded);

        const dryRunDecision = evaluateBatchDryRunExecution({
          projectKey: "vamo",
          snapshot: loaded,
          targetKey: "vamo-place-intelligence",
          targetEnvironment: "staging",
          maxUnits: 2,
          auditReason: "Dry-run before wave approval smoke",
          auditId: "15",
          actor: { type: "operator", id: "operator-smoke" }
        });
        assert.equal(dryRunDecision.ok, true);
        if (!dryRunDecision.ok) {
          throw new Error("dry-run policy should accept");
        }

        await executeBatchDryRun({
          client,
          projectKey: "vamo",
          plan: dryRunDecision.plan,
          now: NOW
        });

        const afterDryRun = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
        assert.ok(afterDryRun);
        assert.equal(afterDryRun.progress.execution.dryRunSucceeded, 2);

        const waveDecision = evaluateBatchStagingCanaryWaveApproval({
          projectKey: "vamo",
          snapshot: afterDryRun,
          principal: adminPrincipal(),
          targetKey: "vamo-place-intelligence",
          targetEnvironment: "staging",
          maxUnits: 1,
          maxRows: 50,
          auditReason: "Approve first bounded staging-canary wave.",
          waveKey: "batch-staging-canary:vamo-eu-poi-sample:audit:wave-smoke",
          now: NOW
        });
        assert.equal(waveDecision.ok, true);
        if (!waveDecision.ok) {
          throw new Error("wave approval policy should accept dry_run_succeeded units");
        }

        await client.query(
          `
            update ingestion_platform.ingestion_batch_queue_items
            set status = 'dry_run_ready'
            where unit_key = $1
          `,
          [waveDecision.plan.unitKeys[0]]
        );
        await assert.rejects(
          () =>
            approveBatchStagingCanaryWave({
              client,
              projectKey: "vamo",
              plan: waveDecision.plan,
              actor: { type: "operator", id: "admin-smoke" },
              now: NOW
            }),
          /could not claim all selected units/
        );
        const rolledBackWaveCount = await client.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_batch_canary_waves`
        );
        assert.equal(rolledBackWaveCount.rows[0]?.count, "0");

        await client.query(
          `
            update ingestion_platform.ingestion_batch_queue_items
            set status = 'dry_run_succeeded'
            where unit_key = $1
          `,
          [waveDecision.plan.unitKeys[0]]
        );

        const approved = await approveBatchStagingCanaryWave({
          client,
          projectKey: "vamo",
          plan: waveDecision.plan,
          actor: { type: "operator", id: "admin-smoke" },
          now: NOW
        });
        assert.equal(approved.idempotentReplay, false);
        assert.equal(approved.unitKeys.length, 1);

        const replay = await approveBatchStagingCanaryWave({
          client,
          projectKey: "vamo",
          plan: waveDecision.plan,
          actor: { type: "operator", id: "admin-smoke" },
          now: NOW
        });
        assert.equal(replay.idempotentReplay, true);

        const waveCount = await client.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_batch_canary_waves`
        );
        assert.equal(waveCount.rows[0]?.count, "1");

        const afterApproval = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
        assert.ok(afterApproval);
        assert.ok(afterApproval.latestWave);
        assert.equal(afterApproval.latestWave.status, "approved");
        assert.equal(afterApproval.latestWave.targetEnvironment, "staging");
        assert.equal(afterApproval.progress.stagingCanary.approved, 1);
        assert.equal(
          afterApproval.items.filter((item) => item.status === "staging_canary_approved").length,
          1
        );

        const secondWaveDecision = evaluateBatchStagingCanaryWaveApproval({
          projectKey: "vamo",
          snapshot: afterApproval,
          principal: adminPrincipal(),
          targetKey: "vamo-place-intelligence",
          targetEnvironment: "staging",
          maxUnits: 5,
          maxRows: 50,
          auditReason: "Second wave should only pick remaining dry_run_succeeded units.",
          waveKey: "batch-staging-canary:vamo-eu-poi-sample:second-wave",
          now: NOW
        });
        assert.equal(secondWaveDecision.ok, true);
        if (!secondWaveDecision.ok) {
          throw new Error("remaining dry_run_succeeded unit should still be eligible");
        }
        assert.equal(secondWaveDecision.plan.unitKeys.length, 1);
        assert.equal(secondWaveDecision.plan.selectedUnits[0]?.status, "dry_run_succeeded");

        const invalidSnapshot = buildBatchQueueSnapshotFromItems({
          planId: afterApproval.planId,
          projectKey: "vamo",
          targetKey: "vamo-place-intelligence",
          targetEnvironment: "staging",
          sourceKey: "fsq-os-places-sample",
          safetyMode: "dry_run",
          items: afterApproval.items.map((item) => ({
            ...item,
            status: "dry_run_ready" as const
          }))
        });
        const blockedDecision = evaluateBatchStagingCanaryWaveApproval({
          projectKey: "vamo",
          snapshot: invalidSnapshot,
          principal: adminPrincipal(),
          targetKey: "vamo-place-intelligence",
          targetEnvironment: "staging",
          maxUnits: 1,
          maxRows: 50,
          auditReason: "Invalid statuses should block wave approval.",
          now: NOW
        });
        assert.equal(blockedDecision.ok, false);
        if (blockedDecision.ok) {
          throw new Error("expected invalid queue statuses to block approval");
        }
        assert.ok(blockedDecision.blocks.some((block) => block.code === "no_eligible_items"));
      } finally {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.end();
      }
    }
  );
});

function adminPrincipal(): AdminPrincipal {
  return {
    provider: "supabase",
    userId: "admin-smoke",
    email: "admin@example.com",
    role: "admin",
    scopes: ["vamo"],
    mfaRequired: true,
    hasVerifiedMfaFactor: true,
    assuranceLevel: "aal2",
    stepUpSatisfiedAt: "2026-07-02T13:58:00.000Z"
  };
}
