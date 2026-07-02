#!/usr/bin/env node

// IP-18 batch target planning dry-run.
//
// Expands a consumer-neutral batch spec into deterministic dry-run units.
// Planning only: no DB writes, no target writes, no live provider calls.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-plan
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-plan -- --spec path/to/batch.yaml
//
// Requires a prior build (the npm script runs `build` first).

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  buildBatchPlan,
  buildBatchPlanView,
  parseBatchPlanSpec
} from "../dist/core/src/index.js";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const defaultSpecPath = resolve(packageRoot, "fixtures/platform/ip18/vamo-eu-poi-batch.yaml");

function readArg(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  return fallback;
}

const specPath = resolve(readArg("--spec", defaultSpecPath));
const previewCount = Number(readArg("--preview", "8"));
const raw = readFileSync(specPath, "utf8");
const parsed = parseBatchPlanSpec(raw);
if (!parsed.ok) {
  console.error("Batch spec validation failed:");
  for (const error of parsed.errors) {
    console.error(`  - [${error.code}] ${error.path}: ${error.message}`);
  }
  process.exit(1);
}

if (parsed.spec.safetyMode !== "dry_run") {
  console.error(`Unsafe safety mode "${parsed.spec.safetyMode}" — IP-18 allows dry_run only.`);
  process.exit(1);
}

const plan = buildBatchPlan({ spec: parsed.spec });
const view = buildBatchPlanView(plan, previewCount);

console.log("IP-18 batch target planning dry-run");
console.log(`- spec: ${specPath}`);
console.log(`- plan id: ${view.planId}`);
console.log(`- target: ${view.targetKey} (${view.targetEnvironment})`);
console.log(`- source: ${view.sourceKey}`);
console.log(`- generated units: ${view.totalUnits}`);
console.log(`- planned: ${view.plannedUnits}`);
console.log(`- blocked: ${view.blockedUnits}`);
console.log("");
console.log("Coverage summary (planned units):");
console.log(`- per country: ${JSON.stringify(view.coverage.perCountry)}`);
console.log(`- per category: ${JSON.stringify(view.coverage.perCategory)}`);
console.log("");
console.log(`First ${view.previewRows.length} planned/blocked units:`);
for (const row of view.previewRows) {
  const blocks = row.blockReasons.length > 0 ? ` blocked: ${row.blockReasons.join(", ")}` : "";
  console.log(
    `  ${row.runOrder}. ${row.unitKey} · ${row.status} · priority ${row.priority}${blocks}`
  );
}
console.log("");
console.log(`Next action: ${view.nextAction}`);
