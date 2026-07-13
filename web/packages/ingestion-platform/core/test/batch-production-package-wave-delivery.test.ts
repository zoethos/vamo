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
import { releaseExpiredProductionPackageWaves } from "../src/batch-production-package-wave-expiry-control.js";
import { executeBatchProductionPackageWave } from "../src/batch-production-package-wave-delivery.js";
import {
  VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
  evaluateProductionPackageWaveApproval
} from "../src/batch-production-package-wave-policy.js";
import { hashProductionPackageCandidateContent } from "../src/production-package-content-hash.js";
import { persistBatchQueueSnapshot } from "../src/batch-queue-control.js";
import { CONTROL_TABLES } from "../src/control-models.js";
import type { StagedCandidate } from "../src/pipeline-runner.js";
import { sampleProgressiveRunSnapshot } from "../src/progressive-read-model.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const placeIntelligenceSql = readFileSync(
  "../../../supabase/migrations/20260625155733_place_intelligence_cache.sql",
  "utf8"
);
const confluendoInboxSql = readFileSync(
  "../../../supabase/migrations/20260701100233_confluendo_inbox.sql",
  "utf8"
);
const writerDigestGrantSql = readFileSync(
  "../../../supabase/migrations/20260701121500_confluendo_inbox_writer_digest_usage.sql",
  "utf8"
);

const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;
const APPROVED_AT = "2026-07-07T10:00:00.000Z";
const EXPIRED_NOW = "2026-07-07T10:20:00.000Z";
const FRESH_NOW = "2026-07-07T10:05:00.000Z";
const STAGING_UNIT_KEY = "vamo-place-intelligence:paris-france:landmark";

describe("releaseExpiredProductionPackageWaves", () => {
  it(
    "releases queue rows, audits transition, and replays idempotently",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetControlSchema(client);
        const approved = await seedApprovedProductionPackageWave(client, {
          approvedAt: APPROVED_AT,
          approvalExpiresAt: "2026-07-07T10:10:00.000Z"
        });

        const first = await releaseExpiredProductionPackageWaves({
          client,
          projectKey: "vamo",
          actor: { type: "operator", id: "expiry-smoke" },
          now: EXPIRED_NOW
        });
        assert.equal(first.released.length, 1);
        assert.equal(first.released[0]?.idempotentReplay, false);
        assert.ok(first.released[0]?.auditId);

        const wave = await client.query<{ status: string }>(
          `select status from ingestion_platform.ingestion_batch_production_package_waves where id = $1::bigint`,
          [approved.waveId]
        );
        assert.equal(wave.rows[0]?.status, "expired");

        const item = await client.query<{ status: string }>(
          `
            select status
            from ingestion_platform.ingestion_batch_production_package_wave_items
            where wave_id = $1::bigint
          `,
          [approved.waveId]
        );
        assert.equal(item.rows[0]?.status, "released");

        const queue = await client.query<{ status: string }>(
          `
            select status
            from ingestion_platform.ingestion_batch_queue_items
            where unit_key = $1
          `,
          [STAGING_UNIT_KEY]
        );
        assert.equal(queue.rows[0]?.status, "staging_canary_succeeded");

        const replay = await releaseExpiredProductionPackageWaves({
          client,
          projectKey: "vamo",
          waveKey: approved.waveKey,
          actor: { type: "operator", id: "expiry-smoke" },
          now: EXPIRED_NOW
        });
        assert.equal(replay.released[0]?.idempotentReplay, true);

        const auditCount = await client.query<{ count: string }>(
          `
            select count(*)::text as count
            from ingestion_platform.ingestion_audit_log
            where action = 'release_expired_production_package_wave'
          `
        );
        assert.equal(auditCount.rows[0]?.count, "1");
      } finally {
        await client.end();
      }
    }
  );

  it(
    "refuses delivery after expiry before any production inbox write",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetControlSchema(client);
        await setupProductionInboxTarget(client);
        const approved = await seedApprovedProductionPackageWave(client, {
          approvedAt: APPROVED_AT,
          approvalExpiresAt: "2026-07-07T10:10:00.000Z"
        });

        await assert.rejects(
          () =>
            executeBatchProductionPackageWave({
              controlClient: client,
              productionInboxConnectionString: databaseUrl,
              projectKey: "vamo",
              targetEnvironment: "production",
              waveKey: approved.waveKey,
              execute: true,
              actor: { type: "operator", id: "delivery-smoke" },
              reason: "should not deliver expired wave",
              proveProduction: () => true,
              deps: {
                loadCandidates: async () => {
                  throw new Error("loadCandidates must not run after expiry");
                }
              },
              now: EXPIRED_NOW
            }),
          /approval_expired|expired/
        );

        const inboxCount = await client.query<{ count: string }>(
          `select count(*)::text as count from confluendo_inbox.shipments`
        );
        assert.equal(inboxCount.rows[0]?.count, "0");
      } finally {
        await cleanupProductionInbox(client);
        await client.end();
      }
    }
  );

  it(
    "preview refuses an expired approval without releasing control rows",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetControlSchema(client);
        const approved = await seedApprovedProductionPackageWave(client, {
          approvedAt: APPROVED_AT,
          approvalExpiresAt: "2026-07-07T10:10:00.000Z"
        });

        await assert.rejects(
          () =>
            executeBatchProductionPackageWave({
              controlClient: client,
              productionInboxConnectionString: databaseUrl,
              projectKey: "vamo",
              targetEnvironment: "production",
              waveKey: approved.waveKey,
              execute: false,
              actor: { type: "operator", id: "delivery-preview" },
              reason: "preview expired wave",
              proveProduction: () => true,
              now: EXPIRED_NOW
            }),
          /approval freshness window has expired|approval_expired/
        );

        const wave = await client.query<{ status: string }>(
          `select status from ingestion_platform.ingestion_batch_production_package_waves where id = $1::bigint`,
          [approved.waveId]
        );
        assert.equal(wave.rows[0]?.status, "approved");

        const queue = await client.query<{ status: string }>(
          `select status from ingestion_platform.ingestion_batch_queue_items where unit_key = $1`,
          [STAGING_UNIT_KEY]
        );
        assert.equal(queue.rows[0]?.status, "production_package_approved");

        const auditCount = await client.query<{ count: string }>(
          `
            select count(*)::text as count
            from ingestion_platform.ingestion_audit_log
            where action = 'release_expired_production_package_wave'
          `
        );
        assert.equal(auditCount.rows[0]?.count, "0");
      } finally {
        await client.end();
      }
    }
  );
});

describe("executeBatchProductionPackageWave", () => {
  it(
    "preview writes nothing",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetControlSchema(client);
        const approved = await seedApprovedProductionPackageWave(client, { now: FRESH_NOW });

        const preview = await executeBatchProductionPackageWave({
          controlClient: client,
          productionInboxConnectionString: databaseUrl,
          projectKey: "vamo",
          targetEnvironment: "production",
          waveKey: approved.waveKey,
          execute: false,
          actor: { type: "operator", id: "delivery-smoke" },
          reason: "preview only",
          proveProduction: () => true,
          now: FRESH_NOW
        });
        assert.equal(preview.previewOnly, true);
        assert.equal(preview.deliveredCount, 0);

        const auditCount = await client.query<{ count: string }>(
          `
            select count(*)::text as count
            from ingestion_platform.ingestion_audit_log
            where action = 'deliver_batch_production_package_wave'
          `
        );
        assert.equal(auditCount.rows[0]?.count, "0");
      } finally {
        await client.end();
      }
    }
  );

  it(
    "orchestration refuses delivery when proveProduction is false before any inbox write",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetControlSchema(client);
        await setupProductionInboxTarget(client);
        const approved = await seedApprovedProductionPackageWave(client, { now: FRESH_NOW });

        let deliverCalled = false;
        const result = await executeBatchProductionPackageWave({
          controlClient: client,
          productionInboxConnectionString: databaseUrl,
          projectKey: "vamo",
          targetEnvironment: "production",
          waveKey: approved.waveKey,
          execute: true,
          actor: { type: "operator", id: "delivery-smoke" },
          reason: "production proof gate",
          proveProduction: () => false,
          deps: {
            deliverPackage: async () => {
              deliverCalled = true;
              throw new Error("deliverPackage must not run when production proof fails");
            },
            loadCandidates: async () => deliveryCandidates()
          },
          now: FRESH_NOW
        });

        assert.equal(deliverCalled, false);
        assert.equal(result.blockedCount, 1);
        assert.equal(result.waveStatus, "blocked");
        assert.equal(result.unitResults[0]?.blockCode, "production_not_proven");

        const inboxCount = await client.query<{ count: string }>(
          `select count(*)::text as count from confluendo_inbox.shipments`
        );
        assert.equal(inboxCount.rows[0]?.count, "0");

        const wave = await client.query<{ status: string; deliveryStatus: string | null }>(
          `
            select status, delivery_status as "deliveryStatus"
            from ingestion_platform.ingestion_batch_production_package_waves
            where id = $1::bigint
          `,
          [approved.waveId]
        );
        assert.equal(wave.rows[0]?.status, "blocked");
        assert.equal(wave.rows[0]?.deliveryStatus, "production_package_blocked");

        const waveItem = await client.query<{ status: string }>(
          `
            select status
            from ingestion_platform.ingestion_batch_production_package_wave_items
            where wave_id = $1::bigint
          `,
          [approved.waveId]
        );
        assert.equal(waveItem.rows[0]?.status, "blocked");

        const queue = await client.query<{ status: string }>(
          `select status from ingestion_platform.ingestion_batch_queue_items where unit_key = $1`,
          [STAGING_UNIT_KEY]
        );
        assert.equal(queue.rows[0]?.status, "production_package_blocked");

        const auditCount = await client.query<{ count: string }>(
          `
            select count(*)::text as count
            from ingestion_platform.ingestion_audit_log
            where action = 'deliver_batch_production_package_wave_blocked'
          `
        );
        assert.equal(auditCount.rows[0]?.count, "1");
      } finally {
        await cleanupProductionInbox(client);
        await client.end();
      }
    }
  );

  it(
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetControlSchema(client);
        await setupProductionInboxTarget(client);
        const approved = await seedApprovedProductionPackageWave(client, { now: FRESH_NOW });
        const candidates = deliveryCandidates();

        const first = await executeBatchProductionPackageWave({
          controlClient: client,
          productionInboxConnectionString: databaseUrl,
          projectKey: "vamo",
          targetEnvironment: "production",
          waveKey: approved.waveKey,
          execute: true,
          actor: { type: "operator", id: "delivery-smoke" },
          reason: "deliver smoke package",
          proveProduction: () => true,
          deps: { loadCandidates: async () => candidates },
          now: FRESH_NOW
        });
        assert.equal(first.previewOnly, false);
        assert.equal(first.deliveredCount, 1);
        assert.equal(first.blockedCount, 0);
        assert.ok(first.unitResults[0]?.checksum);

        const inbox = await client.query<{ package_id: string }>(
          `select package_id from confluendo_inbox.shipments`
        );
        assert.equal(inbox.rows.length, 1);
        assert.equal(inbox.rows[0]?.package_id, first.unitResults[0]?.packageId);

        const wave = await client.query<{ status: string; packageChecksum: string | null }>(
          `
            select status, package_checksum as "packageChecksum"
            from ingestion_platform.ingestion_batch_production_package_waves
            where id = $1::bigint
          `,
          [approved.waveId]
        );
        assert.equal(wave.rows[0]?.status, "delivered");
        assert.equal(wave.rows[0]?.packageChecksum, first.unitResults[0]?.checksum);

        const queue = await client.query<{ status: string }>(
          `select status from ingestion_platform.ingestion_batch_queue_items where unit_key = $1`,
          [STAGING_UNIT_KEY]
        );
        assert.equal(queue.rows[0]?.status, "production_package_delivered");

        const second = await executeBatchProductionPackageWave({
          controlClient: client,
          productionInboxConnectionString: databaseUrl,
          projectKey: "vamo",
          targetEnvironment: "production",
          waveKey: approved.waveKey,
          execute: true,
          actor: { type: "operator", id: "delivery-smoke" },
          reason: "replay smoke package",
          proveProduction: () => true,
          deps: {
            loadCandidates: async () => {
              throw new Error("loadCandidates must not run on idempotent replay");
            }
          },
          now: FRESH_NOW
        });
        assert.equal(second.idempotentReplay, true);
        assert.equal(second.skippedCount, 1);

        const inboxCount = await client.query<{ count: string }>(
          `select count(*)::text as count from confluendo_inbox.shipments`
        );
        assert.equal(inboxCount.rows[0]?.count, "1");
      } finally {
        await cleanupProductionInbox(client);
        await client.end();
      }
    }
  );

  it(
    "blocks checksum mismatch on replay with different package content",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetControlSchema(client);
        await setupProductionInboxTarget(client);
        const approved = await seedApprovedProductionPackageWave(client, { now: FRESH_NOW });

        await executeBatchProductionPackageWave({
          controlClient: client,
          productionInboxConnectionString: databaseUrl,
          projectKey: "vamo",
          targetEnvironment: "production",
          waveKey: approved.waveKey,
          execute: true,
          actor: { type: "operator", id: "delivery-smoke" },
          reason: "initial deliver",
          proveProduction: () => true,
          deps: { loadCandidates: async () => deliveryCandidates() },
          now: FRESH_NOW
        });

        await client.query(
          `
            update ingestion_platform.ingestion_batch_production_package_wave_items
            set status = 'approved', checksum = null, package_id = null
            where wave_id = $1::bigint
          `,
          [approved.waveId]
        );
        await client.query(
          `
            update ingestion_platform.ingestion_batch_production_package_waves
            set status = 'approved', package_checksum = null, package_id = null, delivery_audit_id = null
            where id = $1::bigint
          `,
          [approved.waveId]
        );
        await client.query(
          `
            update ingestion_platform.ingestion_batch_queue_items
            set status = 'production_package_approved'
            where unit_key = $1
          `,
          [STAGING_UNIT_KEY]
        );

        const mismatched = deliveryCandidates();
        mismatched[0]!.payload.location_canonicals = {
          ...(mismatched[0]!.payload.location_canonicals as Record<string, unknown>),
          display_name: "Different Name"
        };

        const result = await executeBatchProductionPackageWave({
          controlClient: client,
          productionInboxConnectionString: databaseUrl,
          projectKey: "vamo",
          targetEnvironment: "production",
          waveKey: approved.waveKey,
          execute: true,
          actor: { type: "operator", id: "delivery-smoke" },
          reason: "checksum mismatch attempt",
          proveProduction: () => true,
          deps: { loadCandidates: async () => mismatched },
          now: FRESH_NOW
        });
        assert.equal(result.blockedCount, 1);
        assert.equal(result.unitResults[0]?.blockCode, "staged_content_drift");
        assert.equal(result.waveStatus, "blocked");

        const wave = await client.query<{ status: string }>(
          `select status from ingestion_platform.ingestion_batch_production_package_waves where id = $1::bigint`,
          [approved.waveId]
        );
        assert.equal(wave.rows[0]?.status, "blocked");

        const waveItem = await client.query<{ status: string }>(
          `
            select status
            from ingestion_platform.ingestion_batch_production_package_wave_items
            where wave_id = $1::bigint
          `,
          [approved.waveId]
        );
        assert.equal(waveItem.rows[0]?.status, "blocked");

        const queue = await client.query<{ status: string }>(
          `select status from ingestion_platform.ingestion_batch_queue_items where unit_key = $1`,
          [STAGING_UNIT_KEY]
        );
        assert.equal(queue.rows[0]?.status, "production_package_blocked");
      } finally {
        await cleanupProductionInbox(client);
        await client.end();
      }
    }
  );

  it(
    "blocks staged content drift before any production inbox write",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await resetControlSchema(client);
        await setupProductionInboxTarget(client);
        const approved = await seedApprovedProductionPackageWave(client, { now: FRESH_NOW });

        const mismatched = deliveryCandidates();
        mismatched[0]!.payload.location_canonicals = {
          ...(mismatched[0]!.payload.location_canonicals as Record<string, unknown>),
          display_name: "Different Name"
        };

        const result = await executeBatchProductionPackageWave({
          controlClient: client,
          productionInboxConnectionString: databaseUrl,
          projectKey: "vamo",
          targetEnvironment: "production",
          waveKey: approved.waveKey,
          execute: true,
          actor: { type: "operator", id: "delivery-smoke" },
          reason: "staged content drift attempt",
          proveProduction: () => true,
          deps: { loadCandidates: async () => mismatched },
          now: FRESH_NOW
        });
        assert.equal(result.blockedCount, 1);
        assert.equal(result.unitResults[0]?.blockCode, "staged_content_drift");
        assert.equal(result.waveStatus, "blocked");

        const inboxCount = await client.query<{ count: string }>(
          `select count(*)::text as count from confluendo_inbox.shipments`
        );
        assert.equal(inboxCount.rows[0]?.count, "0");
      } finally {
        await cleanupProductionInbox(client);
        await client.end();
      }
    }
  );
});

async function resetControlSchema(client: Client): Promise<void> {
  await client.query("drop schema if exists ingestion_platform cascade");
  await client.query(controlSchemaSql);
  assert.equal(CONTROL_TABLES.length, 28);
}

async function seedApprovedProductionPackageWave(
  client: Client,
  input: { now?: string; approvedAt?: string; approvalExpiresAt?: string } = {}
): Promise<{ waveId: string; waveKey: string; packageKey: string }> {
  const now = input.now ?? FRESH_NOW;
  const approvedAt = input.approvedAt ?? now;
  const approvalExpiresAt =
    input.approvalExpiresAt ?? new Date(Date.parse(approvedAt) + 15 * 60 * 1000).toISOString();

  await client.query(
    `insert into ingestion_platform.ingestion_projects (project_key, display_name) values ('vamo', 'Vamo')`
  );

  const parsed = parseBatchPlanSpec(sampleVamoEuPoiBatchYaml());
  assert.equal(parsed.ok, true);
  if (!parsed.ok) throw new Error("sample yaml failed to parse");

  const snapshot = buildBatchQueueSnapshotFromItems({
    planId: "vamo-eu-poi-sample",
    projectKey: "vamo",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    sourceKey: "fsq-os-places-sample",
    safetyMode: "dry_run",
    items: sampleVamoEuPoiBatchQueueSnapshot().items.map((item) =>
      item.unitKey === STAGING_UNIT_KEY
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

  const decision = evaluateProductionPackageWaveApproval({
    projectKey: "vamo",
    snapshot,
    principal: adminPrincipal(approvedAt),
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "production",
    schemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
    maxUnits: 1,
    maxRows: 10,
    maxPackages: 1,
    auditReason: "Approve delivery smoke wave.",
    stagingEvidenceByUnitKey: {
      [STAGING_UNIT_KEY]: { status: "succeeded", shipmentKey: "staging:smoke", shipmentId: "99" }
    },
    now: approvedAt
  });
  assert.equal(decision.ok, true);
  if (!decision.ok) throw new Error("approval should pass");

  const stagedContentHash = hashProductionPackageCandidateContent(deliveryCandidates());
  const approved = await approveBatchProductionPackageWave({
    client,
    projectKey: "vamo",
    plan: {
      ...decision.plan,
      approvedAt,
      approvalExpiresAt,
      selectedUnits: decision.plan.selectedUnits.map((selected) => ({
        ...selected,
        stagingEvidence: {
          ...selected.stagingEvidence,
          stagedContentHash
        }
      }))
    },
    actor: { type: "operator", id: "approval-smoke" },
    now: approvedAt
  });

  await client.query(
    `
      update ingestion_platform.ingestion_batch_production_package_waves
      set approval_expires_at = $2::timestamptz
      where id = $1::bigint
    `,
    [approved.waveId, approvalExpiresAt]
  );

  return {
    waveId: approved.waveId,
    waveKey: approved.waveKey,
    packageKey: approved.waveKey
  };
}

function adminPrincipal(stepUpAt: string = FRESH_NOW): AdminPrincipal {
  return {
    provider: "supabase",
    userId: "admin-smoke",
    email: "admin@vamo.test",
    role: "admin",
    scopes: ["vamo"],
    assuranceLevel: "aal2",
    mfaRequired: true,
    hasVerifiedMfaFactor: true,
    stepUpSatisfiedAt: stepUpAt
  };
}

function deliveryCandidates(): StagedCandidate[] {
  const report = sampleProgressiveRunSnapshot.entries[0]?.report;
  if (!report) {
    throw new Error("sample progressive report missing");
  }
  return [
    {
      recordKey: "fsq_colosseum",
      sourceLineNumber: 1,
      sourceCursor: 1,
      targetProject: "vamo",
      targetProfile: "place-intelligence",
      sourceScope: { geography: "paris-france", category: "landmark" },
      payload: {
        location_canonicals: {
          canonical_key: "fsq-colosseum",
          display_name: "Colosseum",
          name_norm: "colosseum",
          feature_type: "poi",
          country_code: "IT",
          admin1: "Lazio",
          latitude: 41.8902,
          longitude: 12.4922,
          source_provider: "fsq_os_places",
          source_place_id: "fsq_colosseum",
          source_rank: 10,
          attribution: "FSQ Open Source Places",
          confidence: 0.95,
          promotion_state: "seeded"
        },
        location_source_refs: {
          canonical_id: "030d1b0a-a43e-5f7f-bb32-e4ce5a516bc5",
          provider: "fsq_os_places",
          source_place_id: "fsq_colosseum",
          source_payload_hash: "payload-hash",
          attribution: "FSQ Open Source Places",
          fetched_at: "2026-07-01T10:00:00.000Z"
        }
      }
    }
  ];
}

async function setupProductionInboxTarget(client: Client): Promise<void> {
  await cleanupProductionInbox(client);
  await createSupabaseRoles(client);
  await createSupabaseAuthStub(client);
  await createVamoSchemaStub(client);
  await client.query("create schema if not exists extensions");
  await client.query("create extension if not exists pgcrypto with schema extensions");
  await client.query(placeIntelligenceSql);
  await client.query(confluendoInboxSql);
  await client.query(writerDigestGrantSql);
}

async function createSupabaseRoles(client: Client): Promise<void> {
  await client.query(`
    do $$
    begin
      if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
      end if;
      if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
      end if;
      if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin bypassrls;
      end if;
    end;
    $$
  `);
}

async function createSupabaseAuthStub(client: Client): Promise<void> {
  await client.query("create schema if not exists auth");
  await client.query("create table if not exists auth.users (id uuid primary key)");
}

async function createVamoSchemaStub(client: Client): Promise<void> {
  await client.query("create table if not exists public.trips (id uuid primary key)");
}

async function cleanupProductionInbox(client: Client): Promise<void> {
  await client.query("reset role");
  await client.query("drop schema if exists confluendo_guard cascade");
  await client.query("drop schema if exists confluendo_inbox cascade");
  await client.query("drop function if exists public.promote_location_aliases(integer) cascade");
  await client.query("drop table if exists public.location_observations cascade");
  await client.query("drop table if exists public.location_visual_cache cascade");
  await client.query("drop table if exists public.location_resolution_cache cascade");
  await client.query("drop table if exists public.location_aliases cascade");
  await client.query("drop table if exists public.location_source_refs cascade");
  await client.query("drop table if exists public.location_canonicals cascade");
  await client.query("drop table if exists public.location_provider_policies cascade");
  await client.query("drop table if exists public.trips cascade");
  await client.query("drop schema if exists auth cascade");
}
