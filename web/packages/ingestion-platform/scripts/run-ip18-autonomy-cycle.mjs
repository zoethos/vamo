#!/usr/bin/env node

// IP-18.7.1 bounded autonomy cycle harness.
//
// Preview by default. Execute requires --execute and CONFIRM_CONFLUENDO_AUTONOMY_CYCLE=YES.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:autonomy-cycle -- --project-key vamo --policy-key vamo-eu-poi-staging-v1
//   CONFIRM_CONFLUENDO_AUTONOMY_CYCLE=YES INGESTION_CONTROL_DATABASE_URL=... npm --workspace @confluendo/ingestion-platform run ip18:autonomy-cycle -- --execute --project-key vamo --policy-key vamo-eu-poi-staging-v1

import {
  executeAutonomyCycle,
  previewAutonomyCycle
} from "../dist/core/src/autonomy-executor.js";

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
  "--reason"
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

function hasFlag(name) {
  return process.argv.includes(name) || npmConfigValue(name) === "true";
}

const execute = hasFlag("--execute");
const explicitProjectKey = readNamedArg(
  "--project-key",
  readNamedArg("--project", undefined)
);
const explicitPolicyKey = readNamedArg("--policy-key", undefined);
const projectKey =
  explicitProjectKey ??
  (explicitPolicyKey || positionalArgs.length === 1 ? "vamo" : positionalArgs[0] ?? "vamo");
const policyKey =
  explicitPolicyKey ??
  (explicitProjectKey
    ? positionalArgs[0]
    : positionalArgs.length === 1
      ? positionalArgs[0]
      : positionalArgs[1]);
const targetKey = readArg("--target-key", undefined);
const agentId = readArg("--agent-id", "confluendo-autonomy-local");
const reason = readArg("--reason", "IP-18.7.1 bounded autonomy cycle");

const dsn = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
if (!dsn) {
  console.error("INGESTION_CONTROL_DATABASE_URL is required.");
  process.exit(1);
}

const baseInput = {
  connectionString: dsn,
  projectKey,
  policyKey,
  targetKey,
  agentId,
  reason
};

if (!execute) {
  const preview = await previewAutonomyCycle(baseInput);
  const { context } = preview;
  console.log(
    JSON.stringify(
      {
        mode: "preview",
        writes: false,
        policyKey: context.policy.policyKey,
        policyVersion: context.policy.policyVersion,
        targetKey: context.policy.targetKey,
        targetEnvironment: context.policy.targetEnvironment,
        runKey: context.runKey,
        decision: context.evaluation.decision,
        phase: context.evaluation.phase,
        requiredAction: context.evaluation.requiredAction,
        selectedUnitKeys: context.evaluation.selectedUnitKeys,
        maxUnitsApplied: context.evaluation.maxUnitsApplied,
        maxRowsApplied: context.evaluation.maxRowsApplied,
        bounds: {
          maxUnitsPerCycle: context.policy.maxUnitsPerCycle,
          maxRowsPerCycle: context.policy.maxRowsPerCycle
        },
        executionChannel: context.executionChannel,
        pauseReason: context.evaluation.pauseReason,
        recommendedAction: context.evaluation.recommendedAction
      },
      null,
      2
    )
  );
  process.exit(0);
}

if (process.env.CONFIRM_CONFLUENDO_AUTONOMY_CYCLE !== "YES") {
  console.error(
    "Refusing to execute. Set CONFIRM_CONFLUENDO_AUTONOMY_CYCLE=YES to run one bounded control-plane action."
  );
  process.exit(1);
}

if (process.env.VAMO_STAGING_CANARY_APP_DATABASE_URL?.trim()) {
  console.error(
    "Refusing to execute: VAMO_STAGING_CANARY_APP_DATABASE_URL must not be set for IP-18.7.1 autonomy cycles."
  );
  process.exit(1);
}

const result = await executeAutonomyCycle(baseInput);
console.log(
  JSON.stringify(
    {
      mode: "execute",
      runId: result.runId,
      runStatus: result.runStatus,
      idempotentReplay: result.idempotentReplay,
      actionApplied: result.actionApplied,
      deferredReason: result.deferredReason,
      auditId: result.auditId,
      dryRunExecutionKey: result.dryRunExecutionKey,
      waveKey: result.waveKey,
      eventNames: result.eventNames,
      decision: result.context.evaluation.decision,
      requiredAction: result.context.evaluation.requiredAction,
      selectedUnitKeys: result.context.evaluation.selectedUnitKeys,
      executionChannel: result.context.executionChannel
    },
    null,
    2
  )
);
