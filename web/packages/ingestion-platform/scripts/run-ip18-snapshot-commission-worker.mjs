#!/usr/bin/env node

import { randomUUID } from "node:crypto";
import process from "node:process";

import {
  SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_ENV,
  SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
  runSnapshotCommissionWorker
} from "../dist/core/src/snapshot-commission-worker.js";
import {
  FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY_ENV,
  FSQ_OS_PLACES_CATALOG_TOKEN_ENV
} from "../dist/adapters/source/src/index.js";
import { resolveCliSnapshotArtifactStore } from "./snapshot-artifact-store-cli.mjs";

const workerId = readArg("--worker-id") ?? "snapshot-commission-worker";
const workerRunKey = readArg("--worker-run-key") ?? randomUUID();
const controlDsn = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();

if (!controlDsn) {
  console.error("INGESTION_CONTROL_DATABASE_URL is required.");
  process.exit(1);
}

if (process.env[SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_ENV] !== SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE) {
  console.error(
    `Refusing to execute without ${SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_ENV}=${SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE}.`
  );
  process.exit(1);
}

const artifactStoreResolved = await resolveCliSnapshotArtifactStore({});
if (!artifactStoreResolved.ok) {
  console.error("Snapshot artifact store is required for commission worker execution.");
  process.exit(1);
}

const result = await runSnapshotCommissionWorker({
  connectionString: controlDsn,
  workerId,
  workerRunKey,
  confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
  serviceApiKey:
    process.env[FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY_ENV] ??
    process.env[FSQ_OS_PLACES_CATALOG_TOKEN_ENV],
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

console.log("");
console.log("=== IP-18.8.13 Snapshot Commission Worker ===");
console.log(`Outcome: ${result.outcome}`);
console.log(`Request: ${result.requestId}`);
if (result.outcome === "failed") {
  console.log(`Error code: ${result.errorCode}`);
  console.log(`Error message: ${result.errorMessage}`);
} else {
  console.log(`Registered release: ${result.registeredReleaseId}`);
  console.log("Activation remains a separately confirmed operator action.");
}
console.log("");

function readArg(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) {
    return undefined;
  }
  return process.argv[index + 1];
}
