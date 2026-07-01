// IP-17 Vamo Production Inbox delivery runbook CLI.
//
// Preview is safe and requires no secrets. Live execution is gated by all of:
//   - CONFIRM_VAMO_PRODUCTION_INBOX=YES
//   - VAMO_PRODUCTION_INBOX_ENVIRONMENT=production
//   - VAMO_PRODUCTION_INBOX_DATABASE_URL
//   - VAMO_PRODUCTION_INBOX_APPROVAL_ID
//   - INGESTION_CONTROL_DATABASE_URL
//   - --execute
//
// The target adapter writes only into Vamo's `confluendo_inbox` schema and
// computes checksums inside target Postgres. Vamo applies the package later via
// its own apply function.

import { readFileSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "pg";

import {
  buildProductionInboxPackage,
  buildScheduleProposal,
  isProductionInboxApprovalFresh,
  PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS,
  recordProductionInboxDelivery,
  runFixturePipeline,
  runProgressiveDryRun,
  scoreTargetCandidate,
  summarizeWrite
} from "../dist/core/src/index.js";
import {
  deliverPostgresProductionInboxPackage,
  planPostgresDryRun
} from "../dist/adapters/target/src/index.js";
import { parsePipelineSpec, parseTargetProjectSpec } from "../dist/spec/src/index.js";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const bundleDir = resolve(packageRoot, "fixtures/imported/vamo-place-intelligence");
const proposalInputPath = resolve(packageRoot, "fixtures/platform/ip14/proposal-input.json");

const STAGING_HOST_PATTERN = new RegExp(process.env.VAMO_STAGING_HOST_PATTERN ?? "sfwziwcuyctxvidivnsh", "i");

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

async function buildReviewedRun() {
  const input = JSON.parse(readFileSync(proposalInputPath, "utf8"));
  const candidate = input.candidates.find((entry) => entry.targetId === input.primaryTargetId);
  if (!candidate) {
    throw new Error(`IP-17 fixture has no candidate matching primaryTargetId "${input.primaryTargetId}".`);
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
    throw new Error(`IP-17 reviewed proposal was rejected: ${JSON.stringify(proposalResult.errors)}`);
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
  const pipelineRun = await runFixturePipeline({
    pipeline,
    batchSize: proposal.scope.rowLimit,
    fixtureRoot: bundleDir
  });
  const candidates = pipelineRun.candidates.filter((candidate) =>
    candidateMatchesScope(candidate, proposal.scope)
  );
  return { proposal, report, candidates };
}

function makeProveProduction(connectionString) {
  return async () => {
    if (process.env.VAMO_PRODUCTION_INBOX_ENVIRONMENT !== "production") {
      return false;
    }
    if (STAGING_HOST_PATTERN.test(connectionString)) {
      return false;
    }
    return true;
  };
}

function approvalMaxAgeMs() {
  const raw = process.env.VAMO_PRODUCTION_INBOX_APPROVAL_MAX_AGE_MINUTES?.trim();
  if (!raw) {
    return PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS;
  }
  const minutes = Number.parseInt(raw, 10);
  if (!Number.isInteger(minutes) || minutes <= 0 || String(minutes) !== raw) {
    throw new Error(
      `VAMO_PRODUCTION_INBOX_APPROVAL_MAX_AGE_MINUTES must be a positive integer of minutes; got "${raw}".`
    );
  }
  return minutes * 60 * 1000;
}

async function findActiveProductionInboxShipment({ connectionString, projectKey, shipmentKey }) {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const result = await client.query(
      `
        select s.id::text as id, s.status, s.summary
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
      throw new Error(`Recorded production-inbox approval ${approvalId} was not found.`);
    }
    if (row.action !== "approve_production_inbox") {
      throw new Error(`Audit row ${approvalId} is not an approve_production_inbox action.`);
    }
    if (row.projectKey !== projectKey || row.targetId !== targetId) {
      throw new Error(
        `Recorded approval targets ${row.projectKey}/${row.targetId}, not ${projectKey}/${targetId}.`
      );
    }
    if (row.payload?.accepted !== true) {
      throw new Error(`Recorded approval ${approvalId} is not accepted.`);
    }
    return {
      approvalId: row.id,
      reason: row.reason,
      payload: row.payload,
      createdAt: row.createdAt instanceof Date ? row.createdAt.toISOString() : String(row.createdAt),
      actor: { type: row.actorType, id: row.actorId }
    };
  } finally {
    await client.end();
  }
}

function assertApprovalMatchesReviewedRun(approval, { report, write }) {
  const plan = approval.payload?.plan;
  if (!plan || typeof plan !== "object") {
    throw new Error(`Recorded approval ${approval.approvalId} has no plan payload.`);
  }
  const mismatches = [];
  compare(mismatches, "projectKey", plan.projectKey, report.projectKey);
  compare(mismatches, "targetId", plan.targetId, report.targetId);
  compare(mismatches, "sourceId", plan.sourceId, report.sourceId);
  compare(mismatches, "targetEnvironment", plan.targetEnvironment, "production");
  compare(mismatches, "toStatus", plan.toStatus, "production_inbox_delivered");
  compare(mismatches, "write.writeCount", plan.write?.writeCount, write.writeCount);
  compare(mismatches, "write.insert", plan.write?.insert, write.insert);
  compare(mismatches, "write.update", plan.write?.update, write.update);
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

function bullet(label, value) {
  console.log(`  ${label.padEnd(30)} ${value}`);
}

async function main() {
  const execute = process.argv.includes("--execute");
  const confirmed = process.env.CONFIRM_VAMO_PRODUCTION_INBOX === "YES";
  const productionDsn = process.env.VAMO_PRODUCTION_INBOX_DATABASE_URL?.trim();
  const environment = process.env.VAMO_PRODUCTION_INBOX_ENVIRONMENT?.trim();
  const controlDsn = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  const approvalId = process.env.VAMO_PRODUCTION_INBOX_APPROVAL_ID?.trim();

  const { proposal, report, candidates } = await buildReviewedRun();
  const write = summarizeWrite({ runReport: report });

  console.log("");
  console.log("=== IP-17 Vamo Production Inbox Delivery (runbook) ===");
  console.log("(bundled reviewed dry run · consumer inbox only · Vamo applies separately)");
  console.log("");
  bullet("project", report.projectKey);
  bullet("target", report.targetId);
  bullet("source", report.sourceId);
  bullet("reached review", String(report.reachedReview));
  bullet("wrote to target", String(report.wroteToTarget));
  bullet("insert/update/no-op", `${write.insert} / ${write.update} / ${write.noOp}`);
  bullet("write count", String(write.writeCount));
  bullet("candidates", String(candidates.length));
  console.log("");

  if (!report.reachedReview || report.wroteToTarget !== false || !report.shipmentDiff.compatible) {
    console.error("Reviewed run is not eligible for production inbox delivery.");
    process.exit(1);
  }

  const gatesSatisfied =
    confirmed &&
    Boolean(productionDsn) &&
    environment === "production" &&
    Boolean(controlDsn) &&
    Boolean(approvalId);
  if (!gatesSatisfied || !execute) {
    console.log("Confirmation gate");
    bullet("CONFIRM_VAMO_PRODUCTION_INBOX=YES", confirmed ? "yes" : "MISSING");
    bullet("VAMO_PRODUCTION_INBOX_DATABASE_URL", productionDsn ? "set" : "MISSING");
    bullet("VAMO_PRODUCTION_INBOX_ENVIRONMENT", environment === "production" ? "production" : `INVALID (${environment ?? "unset"})`);
    bullet("INGESTION_CONTROL_DATABASE_URL", controlDsn ? "set" : "MISSING");
    bullet("VAMO_PRODUCTION_INBOX_APPROVAL_ID", approvalId ? approvalId : "MISSING");
    bullet("--execute flag", execute ? "yes" : "MISSING");
    console.log("");
    console.error("NO WRITE PERFORMED. Live production-inbox delivery requires every gate above plus --execute.");
    process.exit(1);
  }

  const approval = await loadRecordedApproval({
    connectionString: controlDsn,
    approvalId,
    projectKey: report.projectKey,
    targetId: report.targetId
  });
  assertApprovalMatchesReviewedRun(approval, { report, write });
  const now = new Date().toISOString();
  const maxAgeMs = approvalMaxAgeMs();
  if (!isProductionInboxApprovalFresh({ approvedAt: approval.createdAt, now, maxAgeMs })) {
    console.error(
      `NO WRITE PERFORMED. Recorded approval ${approvalId} is outside the ` +
        `${Math.round(maxAgeMs / 60000)}-minute TTL or is future-dated.`
    );
    process.exit(1);
  }

  const packageId = `production-inbox:${report.targetId}:approval:${approvalId}`;
  const shipmentKey = packageId;
  const existingShipment = await findActiveProductionInboxShipment({
    connectionString: controlDsn,
    projectKey: report.projectKey,
    shipmentKey
  });
  if (existingShipment) {
    console.error(`NO WRITE PERFORMED. Approval ${approvalId} already has shipment ${shipmentKey}.`);
    process.exit(1);
  }

  const pkg = buildProductionInboxPackage({
    packageId,
    consumerKey: report.projectKey,
    runReport: report,
    candidates,
    approvedBy: approval.actor.id,
    approvalReason: approval.reason,
    sourceManifest: {
      sourceId: report.sourceId,
      checkpoint: report.checkpoint,
      scope: proposal.scope
    },
    attributionManifest: {
      sourceId: report.sourceId,
      attribution: "FSQ Open Source Places"
    }
  });

  console.log("All gates satisfied. Delivering to confluendo_inbox only…");
  const delivered = await deliverPostgresProductionInboxPackage({
    connectionString: productionDsn,
    package: pkg,
    proveProduction: makeProveProduction(productionDsn)
  });
  if (!delivered.ok) {
    console.error(`Production inbox delivery refused: [${delivered.code}] ${delivered.message}`);
    process.exit(1);
  }

  const ledger = await recordProductionInboxDelivery({
    connectionString: controlDsn,
    projectKey: report.projectKey,
    targetId: report.targetId,
    targetAdapter: "postgres-production-inbox",
    approvalAuditId: approvalId,
    packageId: delivered.packageId,
    packageChecksum: delivered.checksum,
    itemCount: delivered.itemCount,
    actor: approval.actor,
    reason: approval.reason
  });

  console.log("Production inbox delivered. Vamo apply is a separate consumer-owned step.");
  bullet("package id", delivered.packageId);
  bullet("control shipment id", ledger.shipmentId);
  bullet("item count", String(delivered.itemCount));
  bullet("idempotent", String(delivered.idempotent));
}

main().catch((error) => {
  console.error("IP-17 production-inbox runbook failed:");
  console.error(error instanceof Error ? error.stack ?? error.message : error);
  process.exit(1);
});

function candidateMatchesScope(candidate, scope) {
  return (
    normalizeScope(candidate.sourceScope?.geography) === normalizeScope(scope.geography) &&
    normalizeScope(candidate.sourceScope?.category) === normalizeScope(scope.category)
  );
}

function normalizeScope(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}
