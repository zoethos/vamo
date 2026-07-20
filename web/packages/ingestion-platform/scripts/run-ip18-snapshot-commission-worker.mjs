#!/usr/bin/env node

import { randomUUID } from "node:crypto";
import process from "node:process";

import {
  SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_ENV,
  SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
  runSnapshotCommissionWorker
} from "../dist/core/src/snapshot-commission-worker.js";
import {
  FSQ_PORTAL_QUERY_TIMEOUT_ENV,
  resolveFsqPortalQueryTimeoutMs
} from "../dist/core/src/fsq-portal-query-timeout.js";
import { createDefaultFsqPortalIcebergDuckDbRunner } from "../dist/adapters/source/src/fsq-os-places-portal-iceberg-duckdb.js";
import { resolveCliSnapshotArtifactStore } from "./snapshot-artifact-store-cli.mjs";

const workerId = readArg("--worker-id") ?? "snapshot-commission-worker";
const workerRunKey = readArg("--worker-run-key") ?? randomUUID();
const controlDsn = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
const queryTimeout = resolveFsqPortalQueryTimeoutMs(process.env[FSQ_PORTAL_QUERY_TIMEOUT_ENV]);
const requireHostedArtifactStore = process.argv.includes("--require-hosted-artifact-store");

if (!controlDsn) {
  console.error("INGESTION_CONTROL_DATABASE_URL is required.");
  process.exit(1);
}

if (!queryTimeout.ok) {
  console.error(
    `${FSQ_PORTAL_QUERY_TIMEOUT_ENV} must be a whole number from 30000 through 900000 milliseconds.`
  );
  process.exit(1);
}

if (process.env[SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_ENV] !== SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE) {
  console.error(
    `Refusing to execute without ${SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_ENV}=${SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE}.`
  );
  process.exit(1);
}

const artifactStoreResolved = await resolveCliSnapshotArtifactStore({
  requireHostedStore: requireHostedArtifactStore
});
if (!artifactStoreResolved.ok) {
  console.error("Snapshot artifact store is required for commission worker execution.");
  process.exit(1);
}

const result = await runSnapshotCommissionWorker({
  connectionString: controlDsn,
  workerId,
  workerRunKey,
  confirmation: SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE,
  portalAccessToken: process.env.FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN,
  portalAccessTokenExpiresAt: process.env.FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN_EXPIRES_AT,
  queryTimeoutMs: queryTimeout.timeoutMs,
  duckDbRunner: createDefaultFsqPortalIcebergDuckDbRunner(),
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
  process.exitCode = 1;
} else if (result.outcome === "pending_retry") {
  console.log(`Error code: ${result.errorCode}`);
  console.log(`Error message: ${result.errorMessage}`);
  process.exitCode = 1;
} else {
  console.log(`Registered release: ${result.registeredReleaseId}`);
  console.log("Activation remains a separately confirmed operator action.");
}
console.log("");

// This is a one-shot trusted worker. A timed-out native DuckDB request can keep
// Node's event loop alive after its terminal control-plane outcome is persisted.
process.exit(process.exitCode ?? 0);

function readArg(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) {
    return undefined;
  }
  return process.argv[index + 1];
}
