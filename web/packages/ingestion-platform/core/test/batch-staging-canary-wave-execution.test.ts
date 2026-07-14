import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import { applyPostgresStagingCanary } from "../../adapters/target/src/postgres-staging-canary.js";
import type { TargetProjectSpec } from "../../spec/src/index.js";
import { parseBatchPlanSpec } from "../src/batch-plan-spec.js";
import { sampleVamoEuPoiBatchYaml } from "../src/batch-plan-read-model.js";
import { approveBatchStagingCanaryWave } from "../src/batch-staging-canary-wave-control.js";
import {
  defaultLoadWaveUnitCandidates,
  executeBatchStagingCanaryWave
} from "../src/batch-staging-canary-wave-execution.js";
import { evaluateBatchStagingCanaryWaveApproval } from "../src/batch-staging-canary-wave-policy.js";
import {
  type BatchQueueItem,
  buildBatchQueueSnapshotFromItems,
  sampleVamoEuPoiBatchQueueSnapshot
} from "../src/batch-queue-read-model.js";
import { loadBatchQueueSnapshot } from "../src/batch-queue-control-read.js";
import { persistBatchQueueSnapshot } from "../src/batch-queue-control.js";
import { executeBatchDryRun } from "../src/batch-dry-run-execution.js";
import { evaluateBatchDryRunExecution } from "../src/batch-dry-run-execution-policy.js";
import { scheduleBatchDryRun } from "../src/batch-queue-mutations.js";
import type { AdminPrincipal } from "../src/admin-auth.js";
import type { PipelineRunResult, StagedCandidate } from "../src/pipeline-runner.js";
import { CONTROL_TABLES } from "../src/control-models.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

const NOW = "2026-07-02T14:00:00.000Z";
const WAVE_KEY = "batch-staging-canary:vamo-eu-poi-sample:audit:wave-exec-smoke";

describe("batch staging-canary wave execution", () => {
  it("scans beyond the per-unit row cap before filtering wave candidates by scope", async () => {
    const scopedCandidate = stagingCandidate("paris-landmark", {
      source_id: "paris-landmark",
      display_name: "Paris Landmark"
    });
    scopedCandidate.sourceScope = { geography: "paris-france", category: "landmark" };

    const sourceCandidates = [
      stagingCandidate("rome-poi-1", { source_id: "rome-poi-1", display_name: "Rome 1" }),
      stagingCandidate("rome-poi-2", { source_id: "rome-poi-2", display_name: "Rome 2" }),
      scopedCandidate
    ];
    sourceCandidates[0]!.sourceScope = { geography: "rome-italy", category: "poi" };
    sourceCandidates[1]!.sourceScope = { geography: "rome-italy", category: "poi" };

    let observedBatchSize = 0;
    const loaded = await defaultLoadWaveUnitCandidates({
      unit: {
        unitKey: "vamo-place-intelligence:paris-france:landmark",
        runOrder: 2,
        geography: "paris-france",
        geographyKind: "city",
        country: "france",
        category: "landmark",
        targetKey: "vamo-place-intelligence",
        targetEnvironment: "staging",
        sourceKey: "fsq-os-places-sample",
        priority: 8,
        status: "staging_canary_approved",
        blockReasons: [],
        dryRunReport: null
      } satisfies BatchQueueItem,
      scope: {
        unitKey: "vamo-place-intelligence:paris-france:landmark",
        geography: "paris-france",
        category: "landmark",
        maxRows: 2,
        expectedWrite: { insert: 2, update: 0 }
      },
      pipeline: {} as never,
      fixtureRoot: "",
      runPipeline: async ({ batchSize }) => {
        observedBatchSize = batchSize;
        return {
          candidates: sourceCandidates.slice(0, batchSize),
          policyEvaluations: [],
          events: [],
          deadLetters: [],
          checkpoint: {
            cursorScope: "source_row_id",
            cursorStrategy: "monotonic_row_id",
            cursorValue: { last: batchSize },
            processedCount: Math.min(batchSize, sourceCandidates.length)
          }
        } as PipelineRunResult;
      }
    });

    assert.ok(observedBatchSize > 2);
    assert.deepEqual(
      loaded.map((candidate) => candidate.recordKey),
      ["paris-landmark"]
    );
  });

  it(
    "executes approved wave units, records ledger, and replays idempotently without duplicate staging writes",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetSchemas(client);
        const approved = await seedApprovedWave(client);
        await setupStagingTarget(client, { withSentinel: true });

        const first = await runWaveExecution(client, databaseUrl, approved.waveKey, {
          loadCandidates: async ({ scope }) => buildCandidatesForScope(scope),
          applyUnit: async ({ scope, candidates: scoped, stagingConnectionString, proveStaging }) =>
            applyPostgresStagingCanary({
              connectionString: stagingConnectionString,
              target: stagingTargetSpec(),
              candidates: scoped,
              maxRows: scope.maxRows,
              expectedWrite: scope.expectedWrite,
              proveStaging
            })
        });
        assert.equal(first.idempotentReplay, false);
        assert.equal(first.succeededCount, 1, JSON.stringify(first.unitResults));
        const rowsAfterFirst = await stagingRowCount(client);
        assert.ok(rowsAfterFirst > 0);

        const shipmentCount = await client.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_shipments`
        );
        assert.equal(shipmentCount.rows[0]?.count, "1");

        const second = await runWaveExecution(client, databaseUrl, approved.waveKey, {
          loadCandidates: async ({ scope }) => buildCandidatesForScope(scope),
          applyUnit: async () => {
            throw new Error("applyUnit must not run on idempotent replay");
          }
        });
        assert.equal(second.idempotentReplay, true);
        assert.equal(second.succeededCount, 1);
        assert.equal(await stagingRowCount(client), rowsAfterFirst);
      } finally {
        await client.end();
      }
    }
  );

  it(
    "fails closed when staging sentinel is missing",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetSchemas(client);
        const approved = await seedApprovedWave(client);
        await setupStagingTarget(client, { withSentinel: false });

        const result = await runWaveExecution(client, databaseUrl, approved.waveKey, {
          loadCandidates: async ({ scope }) => buildCandidatesForScope(scope),
          applyUnit: async ({ scope, candidates, stagingConnectionString, proveStaging }) =>
            applyPostgresStagingCanary({
              connectionString: stagingConnectionString,
              target: stagingTargetSpec(),
              candidates,
              maxRows: scope.maxRows,
              expectedWrite: scope.expectedWrite,
              proveStaging
            })
        });
        assert.equal(result.blockedCount, 1);
        assert.equal(result.succeededCount, 0);
        assert.equal(await stagingRowCount(client), 0);
        assert.equal(result.unitResults[0]?.blockCode, "staging_not_proven");
      } finally {
        await client.end();
      }
    }
  );

  it(
    "fails closed for production target environment before staging writes",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetSchemas(client);
        const approved = await seedApprovedWave(client);
        await assert.rejects(
          () =>
            runWaveExecution(client, databaseUrl, approved.waveKey, {
              targetEnvironment: "production",
              loadCandidates: async () => [],
              applyUnit: async () => {
                throw new Error("applyUnit must not run for production environment");
              }
            }),
          /production_environment_forbidden|Wave execution blocked/
        );
      } finally {
        await client.end();
      }
    }
  );

  it(
    "refuses an oversized first wave before any staging writes",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetSchemas(client);
        const approved = await seedApprovedWave(client);
        await setupStagingTarget(client, { withSentinel: true });
        await client.query(
          `
            update ingestion_platform.ingestion_batch_canary_waves
            set max_units = 33
            where id = $1::bigint
          `,
          [approved.waveId]
        );
        for (let index = 2; index <= 33; index += 1) {
          await client.query(
            `
              insert into ingestion_platform.ingestion_batch_canary_wave_items (
                wave_id,
                unit_key,
                run_order,
                status,
                planned_row_count
              )
              values ($1::bigint, $2, $3, 'approved', 1)
            `,
            [approved.waveId, `unit-${index}`, index]
          );
        }

        await assert.rejects(
          () =>
            runWaveExecution(client, databaseUrl, approved.waveKey, {
              maxUnits: 33,
              loadCandidates: async () => {
                throw new Error("loadCandidates must not run when ramp is exceeded");
              },
              applyUnit: async () => {
                throw new Error("applyUnit must not run when ramp is exceeded");
              }
            }),
          /ramp_exceeded|first live staging-canary wave/
        );
        assert.equal(await stagingRowCount(client), 0);
        const wave = await client.query<{ status: string }>(
          `select status from ingestion_platform.ingestion_batch_canary_waves where id = $1::bigint`,
          [approved.waveId]
        );
        assert.equal(wave.rows[0]?.status, "approved");
      } finally {
        await client.end();
      }
    }
  );

  it(
    "fails closed when no eligible wave items remain",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetSchemas(client);
        const approved = await seedApprovedWave(client);
        await client.query(
          `
            update ingestion_platform.ingestion_batch_canary_wave_items
            set status = 'succeeded'
            where wave_id = $1::bigint
          `,
          [approved.waveId]
        );

        await assert.rejects(
          () => runWaveExecution(client, databaseUrl, approved.waveKey),
          /no_pending_items|Wave execution blocked/
        );
      } finally {
        await client.end();
      }
    }
  );

  it(
    "fails closed on incompatible diff and stops the wave",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetSchemas(client);
        const approved = await seedApprovedWave(client);
        await setupStagingTarget(client, { withSentinel: true });

        const result = await runWaveExecution(client, databaseUrl, approved.waveKey, {
          loadCandidates: async () => [
            stagingCandidate("wave-smoke-3", { source_id: "wave-smoke-3", display_name: "Drift" }),
            stagingCandidate("wave-smoke-4", { source_id: "wave-smoke-4", display_name: "Drift 2" })
          ],
          applyUnit: async ({ scope, candidates, stagingConnectionString, proveStaging }) =>
            applyPostgresStagingCanary({
              connectionString: stagingConnectionString,
              target: stagingTargetSpec(),
              candidates,
              maxRows: scope.maxRows,
              expectedWrite: { insert: 1, update: 0 },
              proveStaging
            })
        });
        assert.equal(result.blockedCount, 1);
        assert.equal(result.succeededCount, 0);
        assert.equal(result.unitResults[0]?.blockCode, "diff_drift");
        assert.equal(await stagingRowCount(client), 0);
      } finally {
        await client.end();
      }
    }
  );

  it(
    "fails loud when a target write commits but the control ledger fails",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetSchemas(client);
        const approved = await seedApprovedWave(client);
        await setupStagingTarget(client, { withSentinel: true });
        await client.query(`
          create or replace function ingestion_platform.force_wave_ledger_failure()
          returns trigger
          language plpgsql
          as $$
          begin
            raise exception 'forced wave ledger failure';
          end
          $$
        `);
        await client.query(`
          create trigger force_wave_ledger_failure
          before insert on ingestion_platform.ingestion_shipments
          for each row execute function ingestion_platform.force_wave_ledger_failure()
        `);

        await assert.rejects(
          () =>
            runWaveExecution(client, databaseUrl, approved.waveKey, {
              loadCandidates: async ({ scope }) => buildCandidatesForScope(scope),
              applyUnit: async ({ scope, candidates: scoped, stagingConnectionString, proveStaging }) =>
                applyPostgresStagingCanary({
                  connectionString: stagingConnectionString,
                  target: stagingTargetSpec(),
                  candidates: scoped,
                  maxRows: scope.maxRows,
                  expectedWrite: scope.expectedWrite,
                  proveStaging
                })
            }),
          /TARGET WRITE SUCCEEDED BUT CONTROL LEDGER FAILED/
        );
        assert.ok(await stagingRowCount(client));
        const wave = await client.query<{ status: string }>(
          `select status from ingestion_platform.ingestion_batch_canary_waves where wave_key = $1`,
          [approved.waveKey]
        );
        assert.equal(wave.rows[0]?.status, "approved");
        const shipmentCount = await client.query<{ count: string }>(
          `select count(*)::text as count from ingestion_platform.ingestion_shipments`
        );
        assert.equal(shipmentCount.rows[0]?.count, "0");
      } finally {
        await client.end();
      }
    }
  );
});

async function runWaveExecution(
  client: Client,
  stagingConnectionString: string,
  waveKey: string,
  deps?: {
    targetEnvironment?: string;
    maxUnits?: number;
    loadCandidates?: (input: {
      scope: import("../src/batch-staging-canary-wave-candidates.js").BatchWaveUnitScope;
    }) => Promise<StagedCandidate[]>;
    applyUnit?: NonNullable<Parameters<typeof executeBatchStagingCanaryWave>[0]["deps"]>["applyUnit"];
  }
) {
  return executeBatchStagingCanaryWave({
    controlClient: client,
    stagingConnectionString,
    projectKey: "vamo",
    targetEnvironment: deps?.targetEnvironment ?? "staging",
    waveKey,
    maxUnits: deps?.maxUnits,
    actor: { type: "operator", id: "operator-smoke" },
    reason: "Batch staging-canary wave execution smoke",
    target: stagingTargetSpec(),
    proveStaging: async () => true,
    now: NOW,
    deps: {
      loadCandidates: deps?.loadCandidates
        ? async (input) => deps.loadCandidates!(input)
        : async () => [],
      applyUnit: deps?.applyUnit
    }
  });
}

async function seedApprovedWave(client: Client): Promise<{ waveId: string; waveKey: string }> {
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
    reason: "Schedule for wave execution smoke",
    payload: {}
  });

  const loaded = await loadBatchQueueSnapshot({ client, projectKey: "vamo" });
  assert.ok(loaded);

  const dryRunDecision = evaluateBatchDryRunExecution({
    projectKey: "vamo",
    snapshot: loaded,
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    maxUnits: 1,
    auditReason: "Dry-run before wave execution smoke",
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

  const waveDecision = evaluateBatchStagingCanaryWaveApproval({
    projectKey: "vamo",
    snapshot: afterDryRun,
    principal: adminPrincipal(),
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    maxUnits: 1,
    maxRows: 50,
    auditReason: "Approve wave for execution smoke.",
    waveKey: WAVE_KEY,
    now: NOW
  });
  assert.equal(waveDecision.ok, true);
  if (!waveDecision.ok) {
    throw new Error("wave approval policy should accept");
  }

  const approved = await approveBatchStagingCanaryWave({
    client,
    projectKey: "vamo",
    plan: waveDecision.plan,
    actor: { type: "operator", id: "admin-smoke" },
    now: NOW
  });

  return { waveId: approved.waveId, waveKey: approved.waveKey };
}

async function resetSchemas(client: Client): Promise<void> {
  await client.query("drop schema if exists ingestion_platform cascade");
  await client.query("drop schema if exists canary_target cascade");
  await client.query("drop schema if exists confluendo_guard cascade");
  await client.query(controlSchemaSql);
        assert.equal(CONTROL_TABLES.length, 31);
}

async function setupStagingTarget(
  client: Client,
  options: { withSentinel: boolean }
): Promise<void> {
  if (options.withSentinel) {
    await client.query("create schema if not exists confluendo_guard");
    await client.query(
      `create table if not exists confluendo_guard.environment_sentinel (
         key text primary key,
         value text not null
       )`
    );
    await client.query(
      `insert into confluendo_guard.environment_sentinel (key, value)
       values ('environment', 'staging')
       on conflict (key) do update set value = excluded.value`
    );
  }
  await client.query("create schema if not exists canary_target");
  await client.query(`
    create table if not exists canary_target.generic_places (
      source_id text primary key,
      display_name text not null,
      category text
    )
  `);
}

async function stagingRowCount(client: Client): Promise<number> {
  const result = await client.query<{ count: string }>(
    `select count(*)::text as count from canary_target.generic_places`
  );
  return Number.parseInt(result.rows[0]?.count ?? "0", 10);
}

function stagingTargetSpec(): TargetProjectSpec {
  return {
    normalizedSpecVersion: 1,
    kind: "ingestion.target",
    version: 1,
    id: "vamo-staging-canary",
    name: "Vamo Staging Canary",
    adapter: "postgres",
    engine: {
      type: "postgres",
      dsnEnv: "INGESTION_TEST_DATABASE_URL",
      exposeServiceRoleToBrowser: false
    },
    security: {
      serverSideOnly: true,
      forbidBrowserServiceRole: true,
      requireRlsOnExposedSchemas: false,
      exposedSchemas: [],
      requireExplicitDataApiGrants: false,
      dataApiRoles: [],
      dataApiPrivileges: [],
      writeMode: "approved_write"
    },
    shipment: {
      defaultMode: "approved_write",
      tables: [
        {
          table: "canary_target.generic_places",
          mode: "upsert",
          upsertKeys: ["source_id"]
        }
      ]
    }
  };
}

function stagingCandidate(recordKey: string, payload: Record<string, unknown>): StagedCandidate {
  return {
    recordKey,
    sourceLineNumber: 1,
    sourceCursor: 1,
    targetProject: "vamo",
    targetProfile: "places",
    payload: {
      generic_places: payload
    }
  };
}

function buildCandidatesForScope(scope: { expectedWrite: { insert: number } }): StagedCandidate[] {
  return Array.from({ length: scope.expectedWrite.insert }, (_, index) =>
    stagingCandidate(`wave-smoke-${index + 1}`, {
      source_id: `wave-smoke-${index + 1}`,
      display_name: `Smoke ${index + 1}`
    })
  );
}

function adminPrincipal(overrides: Partial<AdminPrincipal> = {}): AdminPrincipal {
  return {
    provider: "supabase",
    userId: "admin-smoke",
    email: "admin@example.com",
    role: "admin",
    scopes: ["vamo"],
    mfaRequired: true,
    hasVerifiedMfaFactor: true,
    assuranceLevel: "aal2",
    stepUpSatisfiedAt: NOW,
    ...overrides
  };
}
