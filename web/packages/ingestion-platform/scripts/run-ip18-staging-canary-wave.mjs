#!/usr/bin/env node

// IP-18.5.2 batch staging-canary wave execution harness.
//
// Default mode is preview only. Execute requires CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY=YES.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:staging-canary-wave
//   npm --workspace @confluendo/ingestion-platform run ip18:staging-canary-wave -- --wave-key batch-staging-canary:vamo-eu-poi-sample:audit:wave-smoke
//   CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY=YES VAMO_STAGING_CANARY_APP_DATABASE_URL=... INGESTION_CONTROL_DATABASE_URL=... \
//     npm --workspace @confluendo/ingestion-platform run ip18:staging-canary-wave -- --execute --wave-key ...

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  evaluateBatchStagingCanaryWaveExecution,
  executeBatchStagingCanaryWave,
  loadStagingCanaryWave,
  resolveSnapshotCandidateLoader
} from "../dist/core/src/index.js";
import { parsePipelineSpec, parseTargetProjectSpec } from "../dist/spec/src/index.js";
import {
  hasHostedSnapshotArtifactStoreProfile,
  printArtifactStoreResolutionFailure,
  resolveCliSnapshotArtifactStore
} from "./snapshot-artifact-store-cli.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const bundleDir = resolve(packageRoot, "fixtures/imported/vamo-place-intelligence");

const PRODUCTION_HOST_PATTERN = new RegExp(
  process.env.VAMO_PRODUCTION_HOST_PATTERN ?? "prod",
  "i"
);

function readArg(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  return fallback;
}

function readBundle(relativePath) {
  return readFileSync(resolve(bundleDir, relativePath), "utf8");
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

const execute = process.argv.includes("--execute");
const projectKey = readArg("--project", "vamo");
const targetEnvironment = readArg("--target-environment", "staging");
const waveKey = readArg("--wave-key", undefined);
const approvalAuditId = readArg("--approval-audit-id", undefined);
const maxUnits = readArg("--max-units", undefined);
const maxRows = readArg("--max-rows", undefined);
const artifactStoreDir = readArg("--artifact-store-dir", process.env.INGESTION_ARTIFACT_STORE_DIR);
const auditReason = readArg(
  "--audit-reason",
  "IP-18.5.2 batch staging-canary wave execution"
);
const actorId = readArg("--actor-id", "cli-operator");

const controlDsn = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
if (!controlDsn) {
  console.error("INGESTION_CONTROL_DATABASE_URL is required.");
  process.exit(1);
}

if (!waveKey?.trim() && !approvalAuditId?.trim()) {
  console.error("Either --wave-key or --approval-audit-id is required.");
  process.exit(1);
}

const wave = await loadStagingCanaryWave({
  connectionString: controlDsn,
  projectKey,
  waveKey,
  approvalAuditId
});

const decision = evaluateBatchStagingCanaryWaveExecution({
  projectKey,
  targetEnvironment,
  wave,
  maxUnits: maxUnits ? Number(maxUnits) : undefined,
  maxRows: maxRows ? Number(maxRows) : undefined
});

flowHeader();
console.log(`- mode: ${execute ? "execute" : "preview"}`);
console.log(`- project: ${projectKey}`);
console.log(`- target environment: ${targetEnvironment}`);
if (wave) {
  console.log(`- wave: ${wave.waveKey} (${wave.status})`);
  console.log(`- approval audit: ${wave.approvalAuditId ?? "unknown"}`);
}

if (!decision.ok) {
  console.error("");
  console.error("Execution blocked:");
  for (const block of decision.blocks) {
    console.error(`  - [${block.code}] ${block.message}`);
  }
  process.exit(1);
}

console.log("");
console.log("Safety summary:");
for (const line of decision.plan.safetySummary) {
  console.log(`  - ${line}`);
}
console.log("");
console.log(`Pending units (${decision.plan.pendingUnitKeys.length}):`);
for (const unitKey of decision.plan.pendingUnitKeys) {
  const unitPlan = decision.plan.unitPlans.find((plan) => plan.unitKey === unitKey);
  console.log(
    `  - ${unitKey}${unitPlan ? ` · shipment ${unitPlan.shipmentKey}` : ""}`
  );
}

if (!execute) {
  console.log("");
  console.log(
    "Preview only. Re-run with --execute, CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY=YES, and VAMO_STAGING_CANARY_APP_DATABASE_URL to write bounded rows to Vamo staging."
  );
  process.exit(0);
}

const stagingDsn = process.env.VAMO_STAGING_CANARY_APP_DATABASE_URL?.trim();
if (!stagingDsn) {
  console.error("VAMO_STAGING_CANARY_APP_DATABASE_URL is required for execute mode.");
  process.exit(1);
}

if (process.env.CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY !== "YES") {
  console.error("Refusing to execute without CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY=YES.");
  process.exit(1);
}

console.log("");
console.log("Confirmation gate");
console.log(`  CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY=YES`);
console.log(`  VAMO_STAGING_CANARY_APP_DATABASE_URL set`);
console.log(`  VAMO_STAGING_CANARY_ENVIRONMENT=${process.env.VAMO_STAGING_CANARY_ENVIRONMENT ?? "unset (set to staging)"}`);
console.log("");

const { pipeline, target } = loadSpecs();

let artifactStoreDirResolved;
let artifactStore;
if (
  artifactStoreDir?.trim() ||
  hasHostedSnapshotArtifactStoreProfile() ||
  process.env.INGESTION_ARTIFACT_STORE_DIR?.trim()
) {
  const artifactStoreResolved = await resolveCliSnapshotArtifactStore({
    preferLocalDir: artifactStoreDir ? resolve(artifactStoreDir) : undefined
  });
  if (!artifactStoreResolved.ok) {
    printArtifactStoreResolutionFailure(artifactStoreResolved);
    process.exit(1);
  }
  artifactStoreDirResolved = artifactStoreResolved.artifactStoreDir;
  artifactStore = artifactStoreResolved.store;
}

const resolvedLoader = await resolveSnapshotCandidateLoader({
  controlConnectionString: controlDsn,
  projectKey,
  planKey: wave.planKey,
  artifactStoreDir: artifactStoreDirResolved,
  artifactStore,
  pipeline
});

try {
  const result = await executeBatchStagingCanaryWave({
    controlConnectionString: controlDsn,
    stagingConnectionString: stagingDsn,
    projectKey,
    targetEnvironment,
    waveKey,
    approvalAuditId,
    maxUnits: maxUnits ? Number(maxUnits) : undefined,
    maxRows: maxRows ? Number(maxRows) : undefined,
    actor: { type: "operator", id: actorId },
    reason: auditReason,
    target,
    proveStaging: makeProveStaging(stagingDsn),
    deps: {
      loadCandidates: ({ unit, scope }) => resolvedLoader.waveLoader({ unit, scope })
    }
  });

  console.log("");
  console.log(`Wave status: ${result.waveStatus}`);
  console.log(`Execution audit: ${result.executionAuditId ?? "none"}`);
  console.log(`Idempotent replay: ${result.idempotentReplay}`);
  console.log(`Succeeded: ${result.succeededCount} · Blocked: ${result.blockedCount} · Skipped: ${result.skippedCount}`);
  for (const unit of result.unitResults) {
    console.log(
      `  - ${unit.unitKey}: ${unit.status}${unit.shipmentId ? ` · shipment ${unit.shipmentId}` : ""}${unit.shipmentKey ? ` · key ${unit.shipmentKey}` : ""}`
    );
  }
} finally {
  await resolvedLoader.dispose();
}

function flowHeader() {
  console.log("");
  console.log("=== IP-18.5.2 Batch Staging-Canary Wave ===");
  console.log("(per-unit applyPostgresStagingCanary · staging only · stop-on-first-failure)");
  console.log("");
}
