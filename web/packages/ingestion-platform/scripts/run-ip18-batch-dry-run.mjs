#!/usr/bin/env node

// IP-18.4 batch dry-run execution harness.
//
// Default mode is preview only. Execute requires CONFIRM_CONFLUENDO_BATCH_DRY_RUN=YES.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-dry-run
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-dry-run -- --max-units 2 --audit-id 15 --audit-reason "bounded smoke"
//   CONFIRM_CONFLUENDO_BATCH_DRY_RUN=YES INGESTION_CONTROL_DATABASE_URL=... npm --workspace @confluendo/ingestion-platform run ip18:batch-dry-run -- --execute

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { evaluateBatchDryRunExecution } from "../dist/core/src/batch-dry-run-execution-policy.js";
import { executeBatchDryRun } from "../dist/core/src/batch-dry-run-execution.js";
import { loadBatchQueueSnapshot } from "../dist/core/src/batch-queue-control-read.js";
import {
  defaultLoadWaveUnitCandidates,
  runFixturePipeline,
  simulateBatchDryRunUnit,
  STAGING_CANARY_MAX_ROWS
} from "../dist/core/src/index.js";
import { parsePipelineSpec } from "../dist/spec/src/index.js";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const bundleDir = resolve(packageRoot, "fixtures/imported/vamo-place-intelligence");

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

function loadPipeline() {
  const parsed = parsePipelineSpec(readBundle("pipeline.yaml"));
  if (!parsed.ok) {
    throw new Error(`Imported pipeline did not parse: ${JSON.stringify(parsed.errors)}`);
  }
  return parsed.value;
}

async function buildFixtureDryRunReport({ unit, executionKey, now, pipeline }) {
  const candidates = await defaultLoadWaveUnitCandidates({
    unit,
    scope: {
      unitKey: unit.unitKey,
      geography: unit.geography,
      category: unit.category,
      maxRows: STAGING_CANARY_MAX_ROWS,
      expectedWrite: { insert: 0, update: 0 }
    },
    pipeline,
    fixtureRoot: bundleDir,
    runPipeline: runFixturePipeline
  });
  return simulateBatchDryRunUnit({
    executionKey,
    unitKey: unit.unitKey,
    geography: unit.geography,
    category: unit.category,
    targetKey: unit.targetKey,
    targetEnvironment: unit.targetEnvironment,
    candidateCount: candidates.length,
    rowLimit: STAGING_CANARY_MAX_ROWS,
    now
  });
}

const execute = process.argv.includes("--execute");
const projectKey = readArg("--project", "vamo");
const targetKey = readArg("--target-key", "vamo-place-intelligence");
const targetEnvironment = readArg("--target-environment", "staging");
const maxUnits = Number(readArg("--max-units", "3"));
const auditReason = readArg("--audit-reason", "IP-18.4 batch dry-run execution preview");
const auditId = readArg("--audit-id", undefined);
const executionKey = readArg("--execution-key", undefined);
const actorId = readArg("--actor-id", "cli-operator");

const dsn = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
if (!dsn) {
  console.error("INGESTION_CONTROL_DATABASE_URL is required.");
  process.exit(1);
}

const snapshot = await loadBatchQueueSnapshot({ connectionString: dsn, projectKey, targetKey });
if (!snapshot) {
  console.error("No active batch queue snapshot found.");
  process.exit(1);
}

const decision = evaluateBatchDryRunExecution({
  projectKey,
  snapshot,
  targetKey,
  targetEnvironment,
  maxUnits,
  auditReason,
  auditId,
  executionKey,
  actor: { type: "api", id: actorId }
});

console.log("IP-18.4 batch dry-run execution");
console.log(`- mode: ${execute ? "execute" : "preview"}`);
console.log(`- project: ${projectKey}`);
console.log(`- target: ${targetKey} (${targetEnvironment})`);
console.log(`- queue dry_run_ready: ${snapshot.progress.execution.dryRunReady}`);

if (!decision.ok) {
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
console.log(`Execution key: ${decision.plan.executionKey}`);
console.log(`Selected units (${decision.plan.unitKeys.length}):`);
for (const unitKey of decision.plan.unitKeys) {
  console.log(`  - ${unitKey}`);
}

if (!execute) {
  console.log("");
  console.log("Preview only. Re-run with --execute and CONFIRM_CONFLUENDO_BATCH_DRY_RUN=YES to persist control-plane results.");
  process.exit(0);
}

if (process.env.CONFIRM_CONFLUENDO_BATCH_DRY_RUN !== "YES") {
  console.error("Refusing to execute without CONFIRM_CONFLUENDO_BATCH_DRY_RUN=YES.");
  process.exit(1);
}

const pipeline = loadPipeline();
const result = await executeBatchDryRun({
  connectionString: dsn,
  projectKey,
  plan: decision.plan,
  deps: {
    buildUnitReport: (input) => buildFixtureDryRunReport({ ...input, pipeline })
  }
});

console.log("");
console.log(`Execution id: ${result.executionId}`);
console.log(`Idempotent replay: ${result.idempotentReplay}`);
console.log(`Succeeded: ${result.succeededCount}`);
console.log(`Blocked: ${result.blockedCount}`);
console.log(`Audit id: ${result.auditId ?? "none"}`);
