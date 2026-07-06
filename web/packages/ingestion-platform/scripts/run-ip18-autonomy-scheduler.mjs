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

const positionalArgs = process.argv.slice(2).filter((arg) => !arg.startsWith("-"));

function npmConfigName(name) {
  return `npm_config_${name.replace(/^--/, "").replace(/-/g, "_")}`;
}

function readArg(name, fallback, positionalIndex) {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  const envValue = process.env[npmConfigName(name)];
  if (envValue && envValue !== "true") {
    return envValue;
  }
  if (positionalIndex !== undefined && positionalArgs[positionalIndex]) {
    return positionalArgs[positionalIndex];
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
  return process.argv.includes(name) || process.env[npmConfigName(name)] === "true";
}

const execute = hasFlag("--execute");
const projectKey = readArg("--project-key", readArg("--project", "vamo", 0), 0);
const policyKey = readArg("--policy-key", undefined, 1);
const targetKey = readArg("--target-key", undefined);
const agentId = readArg("--agent-id", "confluendo-autonomy-scheduler");
const reason = readArg("--reason", "IP-18.7.3 bounded autonomy scheduler cycle");
const maxCycles = readIntArg("--max-cycles", undefined, 2);
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
  agentId,
  reason,
  maxCycles,
  intervalMs
});

console.log(JSON.stringify(result, null, 2));
