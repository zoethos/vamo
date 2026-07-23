#!/usr/bin/env node

import { randomUUID } from "node:crypto";
import process from "node:process";

import {
  SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_ENV,
  SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_VALUE,
  runSnapshotActivationWorker
} from "../dist/core/src/snapshot-activation-worker.js";
import { resolveCliSnapshotArtifactStore } from "./snapshot-artifact-store-cli.mjs";

const workerId = readArg("--worker-id") ?? "snapshot-activation-worker";
const workerRunKey = readArg("--worker-run-key") ?? randomUUID();
const controlDsn = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
const requireHostedArtifactStore = process.argv.includes("--require-hosted-artifact-store");

if (!controlDsn) {
  console.error("INGESTION_CONTROL_DATABASE_URL is required.");
  process.exit(1);
}
if (process.env[SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_ENV] !== SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_VALUE) {
  console.error(`Refusing to execute without ${SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_ENV}=${SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_VALUE}.`);
  process.exit(1);
}

const artifactStoreResolved = await resolveCliSnapshotArtifactStore({
  requireHostedStore: requireHostedArtifactStore
});
if (!artifactStoreResolved.ok) {
  console.error("Snapshot artifact store is required for activation worker execution.");
  process.exit(1);
}

const result = await runSnapshotActivationWorker({
  connectionString: controlDsn,
  workerId,
  workerRunKey,
  confirmation: SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_VALUE,
  artifactStore: artifactStoreResolved.store,
  artifactStoreBaseDir: artifactStoreResolved.artifactStoreDir
});

if (!result.ok) {
  console.error(`Worker blocked: ${result.blocks.join(", ")}`);
  process.exit(1);
}
if (result.outcome === "idle") {
  console.log(result.message);
  process.exit(0);
}

console.log("\n=== IP-18.8.14 Snapshot Activation Worker ===");
console.log(`Outcome: ${result.outcome}`);
console.log(`Request: ${result.requestId}`);
console.log(`Release: ${result.releaseId}`);
if (result.outcome === "activated") {
  console.log(`Binding: ${result.bindingId}`);
  console.log(`Audit: ${result.auditId}`);
} else {
  console.log(`Error code: ${result.errorCode}`);
  console.log(`Error message: ${result.errorMessage}`);
}

function readArg(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}
