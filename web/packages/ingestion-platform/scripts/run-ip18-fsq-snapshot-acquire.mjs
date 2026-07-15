#!/usr/bin/env node

// IP-18.8.10 FSQ snapshot acquisition.
//
// Preview by default (write-free, token-free). Execute requires --execute,
// CONFIRM_CONFLUENDO_FSQ_SNAPSHOT_ACQUIRE=YES, and FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY
// from the server/job secret store only.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:fsq-snapshot-acquire -- \
//     --countries italy,france --categories poi,landmark
//
//   CONFIRM_CONFLUENDO_FSQ_SNAPSHOT_ACQUIRE=YES \
//   FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY=... \
//   npm --workspace @confluendo/ingestion-platform run ip18:fsq-snapshot-acquire -- \
//     --execute --countries italy --categories poi \
//     --artifact-store-dir /tmp/confluendo-snapshot-artifacts

import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_ENV,
  FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE,
  formatFsqSnapshotAcquireLog,
  isOutputPathInsideRepo,
  runFsqSnapshotAcquire
} from "../dist/core/src/index.js";
import {
  FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY_ENV,
  FSQ_OS_PLACES_CATALOG_TOKEN_ENV
} from "../dist/adapters/source/src/index.js";
import {
  hasHostedSnapshotArtifactStoreProfile,
  printArtifactStoreResolutionFailure,
  resolveCliSnapshotArtifactStore
} from "./snapshot-artifact-store-cli.mjs";

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

function parseCsv(value) {
  if (!value) {
    return [];
  }
  return value
    .split(",")
    .map((entry) => entry.trim().toLowerCase())
    .filter((entry) => entry.length > 0);
}

const execute = hasFlag("--execute");
const countries = parseCsv(readArg("--countries"));
const categories = parseCsv(readArg("--categories"));
const maxRowsPerScope = Number(readArg("--max-rows-per-scope", "250"));
const artifactStoreDir = readArg("--artifact-store-dir");
const projectKey = readArg("--project-key", "vamo");
const actorId = readArg("--actor-id", "fsq-snapshot-acquire-cli");
const auditReason =
  readArg("--audit-reason") ??
  "Register validated FSQ snapshot release after acquisition execute.";
const serviceApiKey =
  process.env[FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY_ENV] ??
  process.env[FSQ_OS_PLACES_CATALOG_TOKEN_ENV];
const controlConnectionString = process.env.INGESTION_CONTROL_DATABASE_URL;

if (countries.length === 0 || categories.length === 0) {
  console.error("Missing required arguments: --countries and --categories are required.");
  process.exit(1);
}

if (execute && !artifactStoreDir && !hasHostedSnapshotArtifactStoreProfile()) {
  console.error(
    "Missing required argument for execute mode: --artifact-store-dir or hosted S3-compatible artifact store env."
  );
  process.exit(1);
}

let artifactStore;
let artifactStoreBaseDir;
if (execute) {
  const artifactStoreResolved = await resolveCliSnapshotArtifactStore({
    preferLocalDir: artifactStoreDir ? resolve(artifactStoreDir) : undefined
  });
  if (!artifactStoreResolved.ok) {
    printArtifactStoreResolutionFailure(artifactStoreResolved);
    process.exit(1);
  }
  artifactStore = artifactStoreResolved.store;
  artifactStoreBaseDir = artifactStoreResolved.artifactStoreDir;
}

console.log("IP-18.8.10 FSQ snapshot acquisition");
console.log(`- mode: ${execute ? "execute" : "preview"}`);
console.log(`- countries: ${countries.join(", ")}`);
console.log(`- categories: ${categories.join(", ")}`);
console.log(`- max rows per scope: ${maxRowsPerScope}`);

const result = await runFsqSnapshotAcquire({
  countries,
  categories,
  maxRowsPerScope,
  preview: !execute,
  confirmation: process.env[FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_ENV],
  serviceApiKey,
  artifactStoreBaseDir,
  artifactStore,
  projectKey,
  controlConnectionString,
  actor: { type: "operator", id: actorId },
  auditReason
});

const logPathParent = mkdtempSync(resolve(tmpdir(), "fsq-snapshot-acquire-log-"));
const logPath = resolve(logPathParent, "acquire-result.json");
try {
  writeFileSync(logPath, formatFsqSnapshotAcquireLog(result, serviceApiKey), "utf8");
} finally {
  rmSync(logPathParent, { recursive: true, force: true });
}

if (!result.ok) {
  console.error("");
  console.error("Acquisition blocked:");
  for (const block of result.blocks) {
    console.error(`  - ${block}`);
  }
  process.exit(1);
}

if (result.result.mode === "preview") {
  console.log("");
  console.log("Preview plan:");
  console.log(`- scopes: ${result.result.plan.scopes.length}`);
  console.log(`- max rows per scope: ${result.result.plan.maxRowsPerScope}`);
  console.log("");
  console.log(result.result.nextAction);
  process.exit(0);
}

if (!result.result.accepted) {
  console.log("");
  console.log("Row review:");
  console.log(`- valid: ${result.result.coverage.validRowCount}`);
  console.log(`- invalid: ${result.result.coverage.invalidRowCount}`);
  console.log(`- duplicate: ${result.result.coverage.duplicateRowCount}`);
  console.log(`- out of scope: ${result.result.coverage.outOfScopeRowCount}`);
  console.error("");
  console.error("Release not accepted:");
  for (const block of result.result.blocks) {
    console.error(`  - ${block}`);
  }
  process.exit(1);
}

if (!execute) {
  console.error("Internal error: accepted execute result without --execute flag.");
  process.exit(1);
}

if (process.env[FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_ENV] !== FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE) {
  console.error(
    `Refusing to execute. Set ${FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_ENV}=${FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE}.`
  );
  process.exit(1);
}

if (!serviceApiKey?.trim()) {
  console.error(
    `Refusing to execute. Set ${FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY_ENV} from the server/job secret store.`
  );
  process.exit(1);
}

const resolvedArtifactDir = artifactStoreBaseDir ? resolve(artifactStoreBaseDir) : undefined;
if (resolvedArtifactDir && isOutputPathInsideRepo({ outputDir: resolvedArtifactDir, repoRoot })) {
  console.error("Refusing to write snapshot artifacts inside the git worktree.");
  process.exit(1);
}

console.log("");
console.log("Release accepted:");
console.log(`- release id: ${result.result.releaseId}`);
console.log(`- artifact key: ${result.result.artifactKey}`);
console.log(`- artifact uri: ${result.result.artifactUri}`);
console.log(`- bundle sha256: ${result.result.bundleSha256}`);
console.log("");
console.log("Row review:");
console.log(`- valid: ${result.result.coverage.validRowCount}`);
console.log(`- invalid: ${result.result.coverage.invalidRowCount}`);
console.log(`- duplicate: ${result.result.coverage.duplicateRowCount}`);
console.log(`- out of scope: ${result.result.coverage.outOfScopeRowCount}`);
console.log("");
console.log("Coverage from valid rows only:");
console.log(`- by country: ${JSON.stringify(result.result.coverage.byCountry)}`);
console.log(`- by POI type: ${JSON.stringify(result.result.coverage.byPoiType)}`);
if (result.result.registryAuditId) {
  console.log("");
  console.log(`Registry audit id: ${result.result.registryAuditId}`);
}
console.log("");
console.log(result.result.nextAction);
