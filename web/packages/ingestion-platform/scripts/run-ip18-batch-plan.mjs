#!/usr/bin/env node

// IP-18 batch target planning dry-run.
//
// Expands a consumer-neutral batch spec into deterministic dry-run units.
// Planning only: no DB writes, no target writes, no live provider calls.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-plan
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-plan -- --spec path/to/batch.yaml
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-plan -- --full-data
//
// Requires a prior build (the npm script runs `build` first).

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  buildBatchFullDataPlanPreview,
  buildBatchPlan,
  buildBatchPlanView,
  parseBatchPlanSpec
} from "../dist/core/src/index.js";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const defaultSpecPath = resolve(packageRoot, "fixtures/platform/ip18/vamo-eu-poi-batch.yaml");
const fullDataSpecPath = resolve(packageRoot, "fixtures/platform/ip18/vamo-eu-full-data-batch.yaml");

function readArg(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  const configValue = readNpmConfigArg(name);
  if (configValue && configValue !== "true") {
    return configValue;
  }
  return fallback;
}

function hasFlag(name) {
  const configValue = readNpmConfigArg(name);
  return process.argv.includes(name) || configValue === "true" || configValue === "";
}

function readNpmConfigArg(name) {
  return process.env[`npm_config_${name.replace(/^--/, "").replace(/-/g, "_")}`];
}

const useFullData = hasFlag("--full-data");
const specPath = resolve(readArg("--spec", useFullData ? fullDataSpecPath : defaultSpecPath));
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
const snapshotSourceRows = readSnapshotSourceRows(parsed.spec);
const fullDataPreview = buildBatchFullDataPlanPreview({
  spec: parsed.spec,
  plan,
  previewUnitKeyLimit: previewCount,
  snapshotSourceRows
});

console.log("IP-18 batch target planning dry-run");
console.log(`- spec: ${specPath}`);
console.log(`- plan id: ${view.planId}`);
console.log(`- target: ${view.targetKey} (${view.targetEnvironment})`);
console.log(`- source: ${view.sourceKey}`);
console.log(`- generated units: ${view.totalUnits}`);
console.log(`- planned: ${view.plannedUnits}`);
console.log(`- blocked: ${view.blockedUnits}`);
if (fullDataPreview.consumerContractRef) {
  console.log(`- consumer contract: ${fullDataPreview.consumerContractRef}`);
}
console.log("");
console.log("Coverage summary (planned units):");
console.log(`- per country: ${JSON.stringify(view.coverage.perCountry)}`);
console.log(`- per category: ${JSON.stringify(view.coverage.perCategory)}`);
if (parsed.spec.volumeProjection || parsed.spec.bounds?.sampleRowLimitPerUnit) {
  console.log("");
  console.log("Volume projection (planning estimate, not available snapshot rows):");
  console.log(`- projected source candidates: ${fullDataPreview.volume.totalSourceCandidates}`);
  console.log(
    `- projected expected target writes: ${fullDataPreview.volume.totalExpectedTargetWrites}`
  );
  console.log(
    `- per category: ${JSON.stringify(
      Object.fromEntries(
        Object.entries(fullDataPreview.volume.perCategory).map(([key, entry]) => [
          key,
          {
            units: entry.unitCount,
            sourceCandidates: entry.sourceCandidates,
            expectedTargetWrites: entry.expectedTargetWrites,
            displayLabel: entry.displayLabel
          }
        ])
      )
    )}`
  );
}
if (fullDataPreview.snapshotSupply) {
  console.log("");
  console.log("Actual local snapshot supply:");
  console.log(`- snapshot rows available now: ${fullDataPreview.snapshotSupply.actualSourceRows}`);
  console.log(
    `- planned units with matching snapshot rows: ${fullDataPreview.snapshotSupply.unitsWithSourceRows}`
  );
  console.log(
    `- planned units without matching snapshot rows: ${fullDataPreview.snapshotSupply.unitsWithoutSourceRows}`
  );
  if (fullDataPreview.snapshotSupply.unitsWithoutSourceRows > 0) {
    console.log(
      "- note: seed preview is broader than current supply; empty units will wait for a larger snapshot."
    );
  }
}
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

function readSnapshotSourceRows(spec) {
  const snapshotPath = spec.source?.connection?.snapshotPath;
  if (typeof snapshotPath !== "string" || snapshotPath.trim().length === 0) {
    return undefined;
  }
  const absolutePath = resolve(packageRoot, snapshotPath);
  return readFileSync(absolutePath, "utf8")
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line));
}
