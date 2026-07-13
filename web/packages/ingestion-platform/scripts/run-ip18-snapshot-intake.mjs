#!/usr/bin/env node

// IP-18.8.9 versioned snapshot intake.
//
// Preview by default (write-free). Execute requires --execute and
// CONFIRM_CONFLUENDO_SNAPSHOT_INTAKE=YES.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:snapshot-intake -- \
//     --manifest path/to/manifest.yaml \
//     --input path/to/export.jsonl \
//     --output-dir /tmp/vamo-snapshot-release
//
//   CONFIRM_CONFLUENDO_SNAPSHOT_INTAKE=YES npm --workspace @confluendo/ingestion-platform run ip18:snapshot-intake -- \
//     --execute --manifest ... --input ... --output-dir ...

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  intakeVersionedSnapshot,
  isOutputPathInsideRepo,
  parseSnapshotReleaseManifest,
  SNAPSHOT_INTAKE_CONFIRMATION_ENV,
  SNAPSHOT_INTAKE_CONFIRMATION_VALUE,
  writeSnapshotIntakeArtifacts
} from "../dist/core/src/index.js";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const repoRoot = resolve(packageRoot, "..", "..");

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

const execute = hasFlag("--execute");
const manifestPath = readArg("--manifest");
const inputPath = readArg("--input");
const outputDir = readArg("--output-dir");

if (!manifestPath || !inputPath || !outputDir) {
  console.error("Missing required arguments: --manifest, --input, and --output-dir are required.");
  process.exit(1);
}

const manifestRaw = readFileSync(resolve(manifestPath), "utf8");
const parsedManifest = parseSnapshotReleaseManifest(manifestRaw);
if (!parsedManifest.ok) {
  console.error("Snapshot release manifest validation failed:");
  for (const error of parsedManifest.errors) {
    console.error(`  - [${error.code}] ${error.path}: ${error.message}`);
  }
  process.exit(1);
}

const inputContent = readFileSync(resolve(inputPath), "utf8");
const result = intakeVersionedSnapshot({
  manifest: parsedManifest.manifest,
  inputContent
});

console.log("IP-18.8.9 versioned snapshot intake");
console.log(`- manifest: ${resolve(manifestPath)}`);
console.log(`- input: ${resolve(inputPath)}`);
console.log(`- output dir: ${resolve(outputDir)}`);
console.log(`- mode: ${execute ? "execute" : "preview"}`);

if (!result.ok) {
  console.error("");
  console.error("Intake blocked:");
  for (const block of result.blocks) {
    console.error(`  - ${block}`);
  }
  process.exit(1);
}

console.log("");
console.log("Input checksum:");
console.log(`- sha256: ${result.inputSha256}`);
console.log("");
console.log("Row review:");
console.log(`- valid: ${result.coverage.validRowCount}`);
console.log(`- invalid: ${result.coverage.invalidRowCount}`);
console.log(`- duplicate: ${result.coverage.duplicateRowCount}`);
console.log(`- out of scope: ${result.coverage.outOfScopeRowCount}`);
console.log("");
console.log("Coverage from valid rows only:");
console.log(`- by country: ${JSON.stringify(result.coverage.byCountry)}`);
console.log(`- by POI type: ${JSON.stringify(result.coverage.byPoiType)}`);

if (result.issues.length > 0) {
  console.log("");
  console.log("Row issues:");
  for (const issue of result.issues.slice(0, 20)) {
    console.log(`  line ${issue.lineNumber}: [${issue.category}] ${issue.reason}`);
  }
  if (result.issues.length > 20) {
    console.log(`  ... ${result.issues.length - 20} more`);
  }
}

if (!result.accepted) {
  console.error("");
  console.error("Release not accepted:");
  for (const block of result.blocks) {
    console.error(`  - ${block}`);
  }
  process.exit(1);
}

console.log("");
console.log("Release accepted:");
console.log(`- release id: ${result.release.releaseId}`);
console.log(`- output sha256: ${result.release.outputSha256}`);

if (!execute) {
  console.log("");
  console.log(
    "Preview only. Re-run with --execute and CONFIRM_CONFLUENDO_SNAPSHOT_INTAKE=YES to write source.jsonl, release.json, and coverage-report.json."
  );
  process.exit(0);
}

if (process.env[SNAPSHOT_INTAKE_CONFIRMATION_ENV] !== SNAPSHOT_INTAKE_CONFIRMATION_VALUE) {
  console.error(
    `Refusing to execute. Set ${SNAPSHOT_INTAKE_CONFIRMATION_ENV}=${SNAPSHOT_INTAKE_CONFIRMATION_VALUE} to write snapshot intake artifacts.`
  );
  process.exit(1);
}

if (isOutputPathInsideRepo({ outputDir: resolve(outputDir), repoRoot })) {
  console.error("Refusing to write snapshot intake artifacts inside the git worktree.");
  process.exit(1);
}

writeSnapshotIntakeArtifacts({
  outputDir: resolve(outputDir),
  artifacts: result.artifacts
});

console.log("");
console.log("Wrote:");
console.log(`- ${resolve(outputDir, "source.jsonl")}`);
console.log(`- ${resolve(outputDir, "release.json")}`);
console.log(`- ${resolve(outputDir, "coverage-report.json")}`);
