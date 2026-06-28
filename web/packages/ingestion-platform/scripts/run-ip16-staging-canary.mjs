// IP-16 First Vamo Staging Canary runbook CLI.
//
// This is the live execution arm for promoting one reviewed dry run to a tiny,
// bounded, reversible write into Vamo STAGING only. It is deliberately hard to
// fire by accident:
//
//   1. It always previews the gated plan first (bundled fixtures, dry).
//   2. It HARD-FAILS (exit 1) and writes nothing unless ALL of these hold:
//        - CONFIRM_VAMO_STAGING_CANARY=YES                (explicit confirmation)
//        - VAMO_STAGING_DATABASE_URL is set               (staging DSN)
//        - VAMO_STAGING_CANARY_ENVIRONMENT=staging         (never "production")
//        - VAMO_STAGING_CANARY_APPROVAL_ID is set          (dashboard approval)
//        - INGESTION_CONTROL_DATABASE_URL is set           (approval + ledger)
//        - the --execute flag is passed
//   3. Even then, the recorded dashboard approval must be recent (TTL, default
//      15 minutes; override with VAMO_STAGING_CANARY_APPROVAL_MAX_AGE_MINUTES)
//      AND single-use: if a succeeded/shipping/approved shipment already exists
//      for the approval id, the run refuses before touching the target DB.
//   4. Even then, the target adapter independently proves the target DB itself
//      declares `ingestion.environment = 'staging'` before any write.
//
// Guarantees:
//   - No production writes. There is no production code path or enum.
//   - No live scraping, no VPN/proxy/evasion (source stays bundled/cacheable).
//   - No secrets required to preview; live execution needs only the staging DSN
//     the operator supplies in the environment.
//   - CI/tests never need live Vamo staging credentials: the default invocation
//     (no env, no flag) previews and hard-fails.
//
// Usage:
//   Preview + gate check (CI-safe, hard-fails):
//     npm --workspace @vamo/ingestion-platform run ip16:staging-canary
//   Live staging write (manual, separately approved — DO NOT run without a
//   green light):
//     CONFIRM_VAMO_STAGING_CANARY=YES \
//     VAMO_STAGING_CANARY_ENVIRONMENT=staging \
//     VAMO_STAGING_DATABASE_URL=postgres://... \
//     VAMO_STAGING_CANARY_APPROVAL_ID=123 \
//     VAMO_STAGING_CANARY_REASON="..." \
//     node scripts/run-ip16-staging-canary.mjs --execute

import { readFileSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "pg";

import {
  buildScheduleProposal,
  isApprovalFresh,
  recordStagingCanaryShipment,
  runFixturePipeline,
  runProgressiveDryRun,
  scoreTargetCandidate,
  STAGING_CANARY_APPROVAL_MAX_AGE_MS,
  summarizeWrite
} from "../dist/core/src/index.js";
import {
  applyPostgresStagingCanary,
  planPostgresDryRun
} from "../dist/adapters/target/src/index.js";
import { parsePipelineSpec, parseTargetProjectSpec } from "../dist/spec/src/index.js";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const bundleDir = resolve(packageRoot, "fixtures/imported/vamo-place-intelligence");
const proposalInputPath = resolve(packageRoot, "fixtures/platform/ip14/proposal-input.json");

const PRODUCTION_HOST_PATTERN = new RegExp(
  process.env.VAMO_PRODUCTION_HOST_PATTERN ?? "prod",
  "i"
);

// Bundled Vamo place-cache shape (mirrors the IP-14 harness). The preview never
// reaches a real database; this lets the shipment diff be planned offline.
const VAMO_PLACE_COLUMNS = {
  location_canonicals: [
    "id", "canonical_key", "display_name", "name_norm", "feature_type",
    "country_code", "admin1", "latitude", "longitude", "source_provider",
    "source_place_id", "source_rank", "attribution", "confidence",
    "promotion_state", "created_at", "updated_at"
  ],
  location_source_refs: [
    "id", "canonical_id", "provider", "source_place_id", "source_payload_hash",
    "attribution", "fetched_at", "expires_at", "created_at"
  ]
};

class BundledTargetSchemaClient {
  async query(sql, values) {
    if (sql.includes("information_schema.tables")) {
      const table = String(values?.[1]);
      return this.result([{ exists: table in VAMO_PLACE_COLUMNS }]);
    }
    if (sql.includes("information_schema.columns")) {
      const table = String(values?.[1]);
      return this.result((VAMO_PLACE_COLUMNS[table] ?? []).map((column) => ({ column_name: column })));
    }
    return this.result([]);
  }

  result(rows) {
    return { rows, rowCount: rows.length, command: "SELECT", oid: 0, fields: [] };
  }
}

function readBundle(relativePath) {
  const target = isAbsolute(relativePath) ? relativePath : resolve(bundleDir, relativePath);
  return readFileSync(target, "utf8");
}

function loadSpecs() {
  const pipeline = parsePipelineSpec(readBundle("pipeline.yaml"));
  const target = parseTargetProjectSpec(readBundle("target.yaml"));
  if (!pipeline.ok) {
    throw new Error(`Imported pipeline did not parse: ${JSON.stringify(pipeline.errors)}`);
  }
  if (!target.ok) {
    throw new Error(`Imported target did not parse: ${JSON.stringify(target.errors)}`);
  }
  return { pipeline: pipeline.value, target: target.value };
}

function bullet(label, value) {
  console.log(`  ${label.padEnd(22)} ${value}`);
}

/** Build a reviewed run report + staged candidates from bundled fixtures. */
async function buildReviewedRun() {
  const input = JSON.parse(readFileSync(proposalInputPath, "utf8"));
  const candidate = input.candidates.find((entry) => entry.targetId === input.primaryTargetId);
  if (!candidate) {
    throw new Error(`IP-16 fixture has no candidate matching primaryTargetId "${input.primaryTargetId}".`);
  }

  const { pipeline, target } = loadSpecs();
  const scorecard = scoreTargetCandidate(candidate);
  const proposalResult = buildScheduleProposal({
    scorecard,
    tier: input.tier,
    safetyMode: input.safetyMode,
    scope: input.scope,
    batchSize: input.batchSize,
    checkpointEveryRows: input.checkpointEveryRows,
    quotaBudget: input.quotaBudget,
    runWindow: input.runWindow,
    stopConditions: input.stopConditions,
    forbidNonDryRun: true
  });
  if (!proposalResult.ok) {
    throw new Error(`IP-16 reviewed proposal was rejected: ${JSON.stringify(proposalResult.errors)}`);
  }
  const proposal = proposalResult.proposal;

  const report = await runProgressiveDryRun(
    { proposal, scorecard, pipeline, target, fixtureRoot: bundleDir },
    {
      runPipeline: (pipelineInput) => runFixturePipeline(pipelineInput),
      planDryRun: ({ target: dryRunTarget, candidates }) =>
        planPostgresDryRun({ client: new BundledTargetSchemaClient(), target: dryRunTarget, candidates })
    }
  );

  // The staged candidates an --execute would ship.
  const pipelineRun = await runFixturePipeline({
    pipeline,
    batchSize: proposal.batchSize,
    fixtureRoot: bundleDir
  });

  return { proposal, scorecard, target, report, candidates: pipelineRun.candidates };
}

/** Extra operator/host-side staging proof; the adapter also requires the DB
 *  sentinel `ingestion.environment = 'staging'` and fails closed if absent. */
function makeProveStaging(connectionString) {
  return async () => {
    if (process.env.VAMO_STAGING_CANARY_ENVIRONMENT !== "staging") {
      return false;
    }
    if (PRODUCTION_HOST_PATTERN.test(connectionString)) {
      return false;
    }
    return true;
  };
}

/** Bounded approval TTL in ms (default 15 min; positive-integer-minutes override). */
function approvalMaxAgeMs() {
  const raw = process.env.VAMO_STAGING_CANARY_APPROVAL_MAX_AGE_MINUTES?.trim();
  if (!raw) {
    return STAGING_CANARY_APPROVAL_MAX_AGE_MS;
  }
  const minutes = Number.parseInt(raw, 10);
  if (!Number.isInteger(minutes) || minutes <= 0 || String(minutes) !== raw) {
    throw new Error(
      `VAMO_STAGING_CANARY_APPROVAL_MAX_AGE_MINUTES must be a positive integer of minutes; got "${raw}".`
    );
  }
  return minutes * 60 * 1000;
}

/**
 * Single-use guard: a live approval may be shipped exactly once. The dashboard
 * approval id keys a shipment row (see recordStagingCanaryShipment). If a row in
 * a still-relevant state already exists, the canary has run (or is running) and
 * must not be replayed against the target.
 */
async function findActiveCanaryShipment({ connectionString, projectKey, shipmentKey }) {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const result = await client.query(
      `
        select s.id::text as id, s.status as status
        from ingestion_platform.ingestion_shipments s
        join ingestion_platform.ingestion_projects p on p.id = s.project_id
        where p.project_key = $1
          and s.shipment_key = $2
          and s.status in ('approved', 'shipping', 'succeeded')
        limit 1
      `,
      [projectKey, shipmentKey]
    );
    return result.rows[0] ?? null;
  } finally {
    await client.end();
  }
}

async function main() {
  const execute = process.argv.includes("--execute");
  const confirmed = process.env.CONFIRM_VAMO_STAGING_CANARY === "YES";
  const stagingDsn = process.env.VAMO_STAGING_DATABASE_URL?.trim();
  const environment = process.env.VAMO_STAGING_CANARY_ENVIRONMENT?.trim();
  const controlDsn = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  const approvalId = process.env.VAMO_STAGING_CANARY_APPROVAL_ID?.trim();

  const { proposal, report, target, candidates } = await buildReviewedRun();
  const bounds = {
    geography: proposal.scope.geography,
    category: proposal.scope.category
  };

  const write = summarizeWrite({ runReport: report });

  console.log("");
  console.log("=== IP-16 First Vamo Staging Canary (runbook) ===");
  console.log("(bundled reviewed dry run · staging only · production shipment blocked)");
  console.log("");
  console.log("Reviewed run");
  bullet("project", report.projectKey);
  bullet("target", report.targetId);
  bullet("source", report.sourceId);
  bullet("reached review", String(report.reachedReview));
  bullet("wrote to target", String(report.wroteToTarget));
  console.log("");
  console.log("Bounded canary plan (preview)");
  bullet("environment", "staging");
  bullet("safety -> shipment", "staging_write -> approved_write");
  bullet("geography", bounds.geography);
  bullet("category", bounds.category);
  bullet("insert/update/no-op", `${write.insert} / ${write.update} / ${write.noOp}`);
  bullet("write count", String(write.writeCount));
  bullet("candidates staged", String(candidates.length));
  console.log("");

  if (!report.reachedReview || report.wroteToTarget !== false || !report.shipmentDiff.compatible) {
    console.error("Reviewed run is not eligible for canary execution; nothing can be shipped.");
    process.exit(1);
  }

  console.log("Reviewed dry run is eligible for operator approval.");
  console.log("Live execution requires a recorded dashboard approval id; the CLI does not fabricate admin/MFA context.");
  console.log("");

  const gatesSatisfied =
    confirmed &&
    Boolean(stagingDsn) &&
    environment === "staging" &&
    Boolean(controlDsn) &&
    Boolean(approvalId);
  if (!gatesSatisfied || !execute) {
    console.log("Confirmation gate");
    bullet("CONFIRM_VAMO_STAGING_CANARY=YES", confirmed ? "yes" : "MISSING");
    bullet("VAMO_STAGING_DATABASE_URL", stagingDsn ? "set" : "MISSING");
    bullet("VAMO_STAGING_CANARY_ENVIRONMENT", environment === "staging" ? "staging" : `INVALID (${environment ?? "unset"})`);
    bullet("INGESTION_CONTROL_DATABASE_URL", controlDsn ? "set" : "MISSING");
    bullet("VAMO_STAGING_CANARY_APPROVAL_ID", approvalId ? approvalId : "MISSING");
    bullet("--execute flag", execute ? "yes" : "MISSING");
    console.log("");
    console.error("NO WRITE PERFORMED. The live staging canary requires every gate above plus --execute.");
    process.exit(1);
  }

  const recordedApproval = await loadRecordedApproval({
    connectionString: controlDsn,
    approvalId,
    projectKey: report.projectKey,
    targetId: report.targetId
  });
  assertApprovalMatchesReviewedRun(recordedApproval, { report, bounds, write });
  const auditReason = String(recordedApproval.reason || process.env.VAMO_STAGING_CANARY_REASON || "").trim();
  if (!auditReason) {
    throw new Error("Recorded approval has no audit reason; refusing to execute.");
  }

  // Approval TTL: a forgotten or replayed approval cannot be acted on much later.
  const now = new Date().toISOString();
  const maxAgeMs = approvalMaxAgeMs();
  if (!isApprovalFresh({ approvedAt: recordedApproval.createdAt, now, maxAgeMs })) {
    console.error(
      `NO WRITE PERFORMED. Recorded approval ${approvalId} (created ${recordedApproval.createdAt}) is outside the ` +
        `${Math.round(maxAgeMs / 60000)}-minute TTL or is future-dated. Re-approve in the dashboard before executing.`
    );
    process.exit(1);
  }

  // Single-use: the dashboard approval id may be shipped at most once. This guard
  // runs against the control DB BEFORE the target adapter is touched, so a replay
  // cannot reach Vamo staging even though the adapter itself is idempotent.
  const shipmentKey = `staging-canary:${report.targetId}:approval:${approvalId}`;
  const existingShipment = await findActiveCanaryShipment({
    connectionString: controlDsn,
    projectKey: report.projectKey,
    shipmentKey
  });
  if (existingShipment) {
    console.error(
      `NO WRITE PERFORMED. Approval ${approvalId} already has a ${existingShipment.status} shipment ` +
        `(${shipmentKey}). Staging canaries are single-use; record a fresh approval for another run.`
    );
    process.exit(1);
  }

  // Live, fully-gated execution. Not run in CI or without an explicit green light.
  console.log("All gates satisfied (fresh, single-use approval). Executing the bounded staging canary…");
  const result = await applyPostgresStagingCanary({
    connectionString: stagingDsn,
    target,
    candidates,
    proveStaging: makeProveStaging(stagingDsn),
    maxRows: 50,
    expectedWrite: { insert: write.insert, update: write.update }
  });

  if (!result.ok) {
    console.error(`Staging canary refused: [${result.code}] ${result.message}`);
    process.exit(1);
  }

  // Target write committed. Record the control ledger so the approval becomes
  // single-use. If THIS fails, the target already changed: stop and reconcile.
  let shipment;
  try {
    shipment = await recordStagingCanaryShipment({
      connectionString: controlDsn,
      projectKey: report.projectKey,
      targetId: report.targetId,
      targetAdapter: target.adapter,
      approvalAuditId: approvalId,
      actor: recordedApproval.actor,
      reason: auditReason,
      counts: result.counts,
      items: result.items
    });
  } catch (ledgerError) {
    console.error("");
    console.error("!!! TARGET WRITE SUCCEEDED BUT CONTROL LEDGER FAILED !!!");
    console.error("Do NOT rerun this canary. The Vamo staging target already changed, but the");
    console.error("control ledger was not recorded, so the single-use guard cannot protect a rerun.");
    console.error('Reconcile manually per STAGING_CANARY_RUNBOOK.md > "Target write succeeded but control ledger failed".');
    console.error(`  approval id:  ${approvalId}`);
    console.error(`  shipment_key: ${shipmentKey}`);
    console.error(`  written:      ${JSON.stringify(result.counts)}`);
    console.error(
      `  canary items: ${JSON.stringify(
        result.items.map((item) => ({
          table: item.targetTable,
          op: item.operation,
          recordKey: item.recordKey,
          keys: item.keys
        }))
      )}`
    );
    console.error(ledgerError instanceof Error ? ledgerError.stack ?? ledgerError.message : String(ledgerError));
    process.exit(1);
  }

  console.log("Staging canary shipped (staging only).");
  bullet("shipment id", shipment.shipmentId);
  bullet("wrote to target", String(result.wroteToTarget));
  bullet("insert/update/no-op", `${result.counts.insert} / ${result.counts.update} / ${result.counts.noOp}`);
  bullet("write count", String(result.counts.writeCount));
  console.log("");
  console.log("Rollback: re-run the documented rollback with the recorded shipment items to");
  console.log("remove inserts and restore updates. See STAGING_CANARY_RUNBOOK.md.");
}

main().catch((error) => {
  console.error("IP-16 staging-canary runbook failed:");
  console.error(error instanceof Error ? error.stack ?? error.message : error);
  process.exit(1);
});

async function loadRecordedApproval({ connectionString, approvalId, projectKey, targetId }) {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const result = await client.query(
      `
        select a.id::text as id,
               a.actor_type as "actorType",
               a.actor_id as "actorId",
               a.reason,
               a.payload,
               a.created_at as "createdAt",
               p.project_key as "projectKey",
               a.target_id as "targetId",
               a.action
        from ingestion_platform.ingestion_audit_log a
        join ingestion_platform.ingestion_projects p on p.id = a.project_id
        where a.id = $1::bigint
        limit 1
      `,
      [approvalId]
    );
    const row = result.rows[0];
    if (!row) {
      throw new Error(`Recorded staging-canary approval ${approvalId} was not found.`);
    }
    if (row.action !== "approve_staging_canary") {
      throw new Error(`Audit row ${approvalId} is not an approve_staging_canary action.`);
    }
    if (row.projectKey !== projectKey || row.targetId !== targetId) {
      throw new Error(
        `Recorded approval targets ${row.projectKey}/${row.targetId}, not ${projectKey}/${targetId}.`
      );
    }
    if (row.payload?.accepted !== true) {
      throw new Error(`Recorded approval ${approvalId} is not accepted.`);
    }
    const createdAt = row.createdAt instanceof Date ? row.createdAt.toISOString() : String(row.createdAt);
    return {
      approvalId: row.id,
      reason: row.reason,
      payload: row.payload,
      createdAt,
      actor: { type: row.actorType, id: row.actorId }
    };
  } finally {
    await client.end();
  }
}

function assertApprovalMatchesReviewedRun(approval, { report, bounds, write }) {
  const plan = approval.payload?.plan;
  if (!plan || typeof plan !== "object") {
    throw new Error(`Recorded approval ${approval.approvalId} has no plan payload.`);
  }

  const mismatches = [];
  compare(mismatches, "projectKey", plan.projectKey, report.projectKey);
  compare(mismatches, "targetId", plan.targetId, report.targetId);
  compare(mismatches, "sourceId", plan.sourceId, report.sourceId);
  compare(mismatches, "environment", plan.environment, "staging");
  compare(mismatches, "safetyMode", plan.safetyMode, "staging_write");
  compare(mismatches, "shipmentMode", plan.shipmentMode, "approved_write");
  compare(mismatches, "bounds.geography", plan.bounds?.geography, bounds.geography);
  compare(mismatches, "bounds.category", plan.bounds?.category, bounds.category);
  compare(mismatches, "write.insert", plan.write?.insert, write.insert);
  compare(mismatches, "write.update", plan.write?.update, write.update);
  compare(mismatches, "write.noOp", plan.write?.noOp, write.noOp);
  compare(mismatches, "write.writeCount", plan.write?.writeCount, write.writeCount);

  if (mismatches.length > 0) {
    throw new Error(
      `Recorded approval ${approval.approvalId} does not match the reviewed run: ${mismatches.join("; ")}`
    );
  }
}

function compare(mismatches, label, actual, expected) {
  if (actual !== expected) {
    mismatches.push(`${label} expected ${JSON.stringify(expected)} got ${JSON.stringify(actual)}`);
  }
}
