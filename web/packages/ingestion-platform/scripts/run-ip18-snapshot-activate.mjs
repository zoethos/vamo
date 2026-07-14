#!/usr/bin/env node

// IP-18.8.11 snapshot release activation.
//
// Preview by default (write-free). Execute requires --execute,
// CONFIRM_CONFLUENDO_SNAPSHOT_RELEASE_ACTIVATION=YES, INGESTION_CONTROL_DATABASE_URL,
// --release-id, --plan-key, --artifact-store-dir, and --audit-reason.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:snapshot-activate -- \
//     --release-id fsq_os_places-20260701-deadbeefcafe \
//     --plan-key vamo-eu-full-data-v1 \
//     --artifact-store-dir /tmp/confluendo-snapshot-artifacts \
//     --audit-reason "Activate reviewed FSQ release for full-data queue."
//
//   CONFIRM_CONFLUENDO_SNAPSHOT_RELEASE_ACTIVATION=YES \
//   INGESTION_CONTROL_DATABASE_URL=... \
//   npm --workspace @confluendo/ingestion-platform run ip18:snapshot-activate -- \
//     --execute --release-id ... --plan-key vamo-eu-full-data-v1 \
//     --artifact-store-dir /tmp/confluendo-snapshot-artifacts \
//     --audit-reason "Activate reviewed FSQ release for full-data queue."

import { resolve } from "node:path";

import {
  SNAPSHOT_ACTIVATION_CONFIRMATION_ENV,
  SNAPSHOT_ACTIVATION_CONFIRMATION_VALUE,
  runSnapshotReleaseActivation
} from "../dist/core/src/index.js";
import {
  printArtifactStoreResolutionFailure,
  resolveCliSnapshotArtifactStore
} from "./snapshot-artifact-store-cli.mjs";

function readArg(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  const configValue = process.env[`npm_config_${name.replace(/^--/, "").replace(/-/g, "_")}`];
  if (configValue && configValue !== "true") {
    return configValue;
  }
  return fallback;
}

function hasFlag(name) {
  const configValue = process.env[`npm_config_${name.replace(/^--/, "").replace(/-/g, "_")}`];
  return process.argv.includes(name) || configValue === "true" || configValue === "";
}

const execute = hasFlag("--execute");
const releaseId = readArg("--release-id");
const planKey = readArg("--plan-key", "vamo-eu-full-data-v1");
const projectKey = readArg("--project-key", "vamo");
const artifactStoreDir = readArg("--artifact-store-dir");
const actorId = readArg("--actor-id", "snapshot-activate-cli");
const auditReason =
  readArg("--audit-reason") ??
  "Activate verified snapshot release and reconcile batch queue supply.";
const controlConnectionString = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();

if (!releaseId?.trim()) {
  console.error("Missing required argument: --release-id");
  process.exit(1);
}

if (!controlConnectionString) {
  console.error("INGESTION_CONTROL_DATABASE_URL is required.");
  process.exit(1);
}

const artifactStoreResolved = await resolveCliSnapshotArtifactStore({
  preferLocalDir: artifactStoreDir ? resolve(artifactStoreDir) : undefined
});
if (!artifactStoreResolved.ok) {
  printArtifactStoreResolutionFailure(artifactStoreResolved);
  process.exit(1);
}

console.log("IP-18.8.11 snapshot release activation");
console.log(`- mode: ${execute ? "execute" : "preview"}`);
console.log(`- project: ${projectKey}`);
console.log(`- plan: ${planKey}`);
console.log(`- release id: ${releaseId}`);

const result = await runSnapshotReleaseActivation({
  preview: !execute,
  confirmation: process.env[SNAPSHOT_ACTIVATION_CONFIRMATION_ENV],
  projectKey,
  planKey,
  releaseId,
  artifactStoreDir: artifactStoreResolved.artifactStoreDir,
  artifactStore: artifactStoreResolved.store,
  connectionString: controlConnectionString,
  actor: { type: "operator", id: actorId },
  auditReason
});

if (!result.ok) {
  console.error("");
  console.error("Activation blocked:");
  for (const block of result.blocks) {
    console.error(`  - ${block}`);
  }
  process.exit(1);
}

if (result.result.mode === "preview") {
  console.log("");
  console.log("Verified artifact identity:");
  console.log(`- artifact key: ${result.result.artifactIdentity.artifactKey}`);
  console.log(`- bundle sha256: ${result.result.artifactIdentity.bundleSha256}`);
  console.log(`- output sha256: ${result.result.artifactIdentity.outputSha256}`);
  console.log("");
  console.log("Queue reconciliation preview:");
  console.log(`- changed scopes: ${result.result.queueChanges.changedUnitKeys.length}`);
  console.log(`- supply ready: ${result.result.queueChanges.supplyReadyCount}`);
  console.log(`- parked empty: ${result.result.queueChanges.parkedCount}`);
  console.log(`- preserved in-flight/terminal: ${result.result.queueChanges.preservedCount}`);
  console.log(`- total units: ${result.result.queueChanges.totalUnits}`);
  console.log("");
  console.log(result.result.nextAction);
  console.log("");
  console.log(
    `Re-run with --execute and ${SNAPSHOT_ACTIVATION_CONFIRMATION_ENV}=${SNAPSHOT_ACTIVATION_CONFIRMATION_VALUE} to bind the release and reconcile supply atomically.`
  );
  process.exit(0);
}

if (process.env[SNAPSHOT_ACTIVATION_CONFIRMATION_ENV] !== SNAPSHOT_ACTIVATION_CONFIRMATION_VALUE) {
  console.error(
    `Refusing to execute. Set ${SNAPSHOT_ACTIVATION_CONFIRMATION_ENV}=${SNAPSHOT_ACTIVATION_CONFIRMATION_VALUE}.`
  );
  process.exit(1);
}

console.log("");
console.log("Activation committed:");
console.log(`- binding id: ${result.result.bindingId}`);
console.log(`- audit id: ${result.result.auditId}`);
console.log(`- release id: ${result.result.releaseId}`);
console.log(`- plan: ${result.result.planKey}`);
console.log("");
console.log("Queue reconciliation:");
console.log(`- changed scopes: ${result.result.queueChanges.changedUnitKeys.length}`);
console.log(`- supply ready: ${result.result.queueChanges.supplyReadyCount}`);
console.log(`- parked empty: ${result.result.queueChanges.parkedCount}`);
console.log(`- preserved in-flight/terminal: ${result.result.queueChanges.preservedCount}`);
