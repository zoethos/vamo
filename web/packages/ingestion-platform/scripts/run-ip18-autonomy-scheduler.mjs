#!/usr/bin/env node

// IP-18.7.3 autonomy scheduler harness.
//
// Preview by default. Execute requires --execute and
// CONFIRM_CONFLUENDO_AUTONOMY_SCHEDULER=YES.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:autonomy-scheduler -- --project-key vamo --policy-key vamo-eu-poi-staging-v1
//   CONFIRM_CONFLUENDO_AUTONOMY_SCHEDULER=YES INGESTION_CONTROL_DATABASE_URL=... npm --workspace @confluendo/ingestion-platform run ip18:autonomy-scheduler -- --execute --project-key vamo --policy-key vamo-eu-poi-staging-v1 --max-cycles 10

import { runAutonomyScheduler } from "../dist/core/src/autonomy-scheduler.js";
import {
  hasHostedSnapshotArtifactStoreProfile,
  printArtifactStoreResolutionFailure,
  resolveCliSnapshotArtifactStore
} from "./snapshot-artifact-store-cli.mjs";

function npmConfigName(name) {
  return `npm_config_${name.replace(/^--/, "").replace(/-/g, "_")}`;
}

function npmConfigValue(name) {
  return (
    process.env[npmConfigName(name)] ??
    process.env[`npm_config_${name.replace(/^--/, "")}`]
  );
}

function knownNamedArgValues(names) {
  return new Set(
    names
      .map((name) => npmConfigValue(name))
      .filter((value) => value && value !== "true")
  );
}

const VALUE_FLAGS = new Set([
  "--project-key",
  "--project",
  "--policy-key",
  "--target-key",
  "--agent-id",
  "--reason",
  "--max-cycles",
  "--interval-ms"
]);

function collectPositionalArgs(argv, knownValues) {
  const args = [];
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg.startsWith("--")) {
      if (
        VALUE_FLAGS.has(arg) &&
        index + 1 < argv.length &&
        !argv[index + 1].startsWith("-")
      ) {
        index += 1;
      }
      continue;
    }
    if (!arg.startsWith("-") && !knownValues.has(arg)) {
      args.push(arg);
    }
  }
  return args;
}

const positionalArgs = collectPositionalArgs(
  process.argv.slice(2),
  knownNamedArgValues([...VALUE_FLAGS])
);

function readArg(name, fallback, positionalIndex) {
  const named = readNamedArg(name, undefined);
  if (named !== undefined) {
    return named;
  }
  if (positionalIndex !== undefined && positionalArgs[positionalIndex]) {
    return positionalArgs[positionalIndex];
  }
  return fallback;
}

function readNamedArg(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  const envValue = npmConfigValue(name);
  if (envValue && envValue !== "true") {
    return envValue;
  }
  return fallback;
}

function readIntArg(name, fallback, positionalIndex) {
  const raw = readArg(name, undefined, positionalIndex);
  if (raw === undefined) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value)) {
    console.error(`${name} must be an integer.`);
    process.exit(1);
  }
  return value;
}

function hasFlag(name) {
  return process.argv.includes(name) || npmConfigValue(name) === "true";
}

const execute = hasFlag("--execute");
const explicitProjectKey = readNamedArg(
  "--project-key",
  readNamedArg("--project", undefined)
);
const explicitPolicyKey = readNamedArg("--policy-key", undefined);
const positionalLooksLikePolicyAndMaxCycles =
  positionalArgs.length >= 2 && Number.isInteger(Number(positionalArgs[1]));
const projectKey =
  explicitProjectKey ??
  (explicitPolicyKey || positionalArgs.length === 1 || positionalLooksLikePolicyAndMaxCycles
    ? "vamo"
    : positionalArgs[0] ?? "vamo");
const policyKey =
  explicitPolicyKey ??
  (explicitProjectKey
    ? positionalArgs[0]
    : positionalLooksLikePolicyAndMaxCycles || positionalArgs.length === 1
      ? positionalArgs[0]
      : positionalArgs[1]);
const targetKey = readArg("--target-key", undefined);
const batchPlanKey = readArg("--batch-plan-key", undefined);
const agentId = readArg("--agent-id", "confluendo-autonomy-scheduler");
const reason = readArg("--reason", "IP-18.7.3 bounded autonomy scheduler cycle");
const positionalMaxCycles =
  positionalLooksLikePolicyAndMaxCycles
    ? Number(positionalArgs[1])
    : Number.isInteger(Number(positionalArgs[2]))
      ? Number(positionalArgs[2])
      : undefined;
const maxCycles = readIntArg("--max-cycles", positionalMaxCycles);
const intervalMs = readIntArg("--interval-ms", 0);

const dsn = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
if (!dsn) {
  console.error("INGESTION_CONTROL_DATABASE_URL is required.");
  process.exit(1);
}

if (execute && process.env.CONFIRM_CONFLUENDO_AUTONOMY_SCHEDULER !== "YES") {
  console.error(
    "Refusing to execute. Set CONFIRM_CONFLUENDO_AUTONOMY_SCHEDULER=YES to run bounded scheduled autonomy cycles."
  );
  process.exit(1);
}

if (execute && process.env.VAMO_STAGING_CANARY_APP_DATABASE_URL?.trim()) {
  console.error(
    "Refusing to execute: VAMO_STAGING_CANARY_APP_DATABASE_URL must not be set for IP-18.7.3 autonomy scheduler cycles."
  );
  process.exit(1);
}

const result = await runAutonomyScheduler({
  mode: execute ? "execute" : "preview",
  connectionString: dsn,
  projectKey,
  policyKey,
  targetKey,
  batchPlanKey,
  agentId,
  reason,
  maxCycles,
  intervalMs,
  artifactStoreDir: process.env.INGESTION_ARTIFACT_STORE_DIR?.trim(),
  ...(await resolveOptionalArtifactStoreInput())
});

console.log(JSON.stringify(result, null, 2));

async function resolveOptionalArtifactStoreInput() {
  if (
    !process.env.INGESTION_ARTIFACT_STORE_DIR?.trim() &&
    !hasHostedSnapshotArtifactStoreProfile()
  ) {
    return {};
  }
  const artifactStoreResolved = await resolveCliSnapshotArtifactStore({
    preferLocalDir: process.env.INGESTION_ARTIFACT_STORE_DIR?.trim()
  });
  if (!artifactStoreResolved.ok) {
    printArtifactStoreResolutionFailure(artifactStoreResolved);
    process.exit(1);
  }
  return {
    artifactStoreDir: artifactStoreResolved.artifactStoreDir,
    artifactStore: artifactStoreResolved.store
  };
}
