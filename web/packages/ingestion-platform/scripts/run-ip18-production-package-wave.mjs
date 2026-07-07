#!/usr/bin/env node

// IP-18.6.3 production package-wave delivery harness.
//
// Preview is safe and writes nothing. Execute requires all of:
//   - --execute
//   - CONFIRM_CONFLUENDO_PRODUCTION_PACKAGE_WAVE=YES
//   - INGESTION_CONTROL_DATABASE_URL
//   - VAMO_PRODUCTION_INBOX_DATABASE_URL
//   - VAMO_PRODUCTION_INBOX_ENVIRONMENT=production
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:production-package-wave -- --wave-key <waveKey>
//   CONFIRM_CONFLUENDO_PRODUCTION_PACKAGE_WAVE=YES ... npm --workspace @confluendo/ingestion-platform run ip18:production-package-wave -- --execute --approval-audit-id <id>

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  defaultLoadProductionPackageWaveCandidates,
  executeBatchProductionPackageWave,
  runFixturePipeline
} from "../dist/core/src/index.js";
import { parsePipelineSpec } from "../dist/spec/src/index.js";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const bundleDir = resolve(packageRoot, "fixtures/imported/vamo-place-intelligence");

const STAGING_HOST_PATTERN = new RegExp(
  process.env.VAMO_STAGING_HOST_PATTERN ?? "sfwziwcuyctxvidivnsh",
  "i"
);

function readArg(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  return fallback;
}

function readBundle(relativePath) {
  return readFileSync(resolve(bundleDir, relativePath), "utf8");
}

function loadPipeline() {
  const pipeline = parsePipelineSpec(readBundle("pipeline.yaml"));
  if (!pipeline.ok) {
    throw new Error(`Imported pipeline did not parse: ${JSON.stringify(pipeline.errors)}`);
  }
  return pipeline.value;
}

function makeProveProduction(connectionString) {
  return async () => {
    if (process.env.VAMO_PRODUCTION_INBOX_ENVIRONMENT !== "production") {
      return false;
    }
    if (STAGING_HOST_PATTERN.test(connectionString)) {
      return false;
    }
    return true;
  };
}

function bullet(label, value) {
  console.log(`  ${label.padEnd(34)} ${value}`);
}

const execute = process.argv.includes("--execute");
const confirmed = process.env.CONFIRM_CONFLUENDO_PRODUCTION_PACKAGE_WAVE === "YES";
const controlDsn = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
const productionDsn = process.env.VAMO_PRODUCTION_INBOX_DATABASE_URL?.trim();
const environment = process.env.VAMO_PRODUCTION_INBOX_ENVIRONMENT?.trim();
const projectKey = readArg("--project", "vamo");
const targetEnvironment = readArg("--target-environment", "production");
const waveKey = readArg("--wave-key", undefined);
const approvalAuditId = readArg("--approval-audit-id", undefined);
const maxUnits = readArg("--max-units", undefined);
const maxRows = readArg("--max-rows", undefined);
const maxPackages = readArg("--max-packages", undefined);
const auditReason = readArg(
  "--audit-reason",
  "IP-18.6.3 confirmation-gated production package-wave delivery"
);
const actorId = readArg("--actor-id", "cli-operator");

if (!controlDsn) {
  console.error("INGESTION_CONTROL_DATABASE_URL is required.");
  process.exit(1);
}

if (!waveKey?.trim() && !approvalAuditId?.trim()) {
  console.error("Either --wave-key or --approval-audit-id is required.");
  process.exit(1);
}

const pipeline = loadPipeline();

const result = await executeBatchProductionPackageWave({
  controlConnectionString: controlDsn,
  productionInboxConnectionString: productionDsn,
  projectKey,
  targetEnvironment,
  waveKey,
  approvalAuditId,
  maxUnits: maxUnits ? Number.parseInt(maxUnits, 10) : undefined,
  maxRows: maxRows ? Number.parseInt(maxRows, 10) : undefined,
  maxPackages: maxPackages ? Number.parseInt(maxPackages, 10) : undefined,
  execute: execute && confirmed && environment === "production" && Boolean(productionDsn),
  actor: { type: "operator", id: actorId },
  reason: auditReason,
  proveProduction: productionDsn ? makeProveProduction(productionDsn) : async () => false,
  deps: {
    loadCandidates: ({ unit, scope }) =>
      defaultLoadProductionPackageWaveCandidates({
        unit,
        scope,
        pipeline,
        fixtureRoot: bundleDir,
        runPipeline: (input) => runFixturePipeline(input)
      })
  }
});

console.log("");
console.log("=== IP-18.6.3 Production Package-Wave Delivery ===");
console.log("(IP-17 inbox adapter · consumer apply remains Vamo-owned)");
console.log("");
bullet("project", projectKey);
bullet("wave key", result.waveKey);
bullet("wave status", result.waveStatus);
bullet("preview only", String(result.previewOnly));
bullet("pending units", result.plan.pendingUnitKeys.join(", ") || "(none)");
bullet("delivered units", String(result.deliveredCount));
bullet("skipped units", String(result.skippedCount));
bullet("blocked units", String(result.blockedCount));
console.log("");

if (!execute || !confirmed || environment !== "production" || !productionDsn) {
  console.log("Confirmation gate");
  bullet("CONFIRM_CONFLUENDO_PRODUCTION_PACKAGE_WAVE=YES", confirmed ? "yes" : "MISSING");
  bullet("VAMO_PRODUCTION_INBOX_DATABASE_URL", productionDsn ? "set" : "MISSING");
  bullet(
    "VAMO_PRODUCTION_INBOX_ENVIRONMENT",
    environment === "production" ? "production" : `INVALID (${environment ?? "unset"})`
  );
  bullet("INGESTION_CONTROL_DATABASE_URL", controlDsn ? "set" : "MISSING");
  bullet("--execute flag", execute ? "yes" : "MISSING");
  console.log("");
  console.log("Safety summary");
  for (const line of result.safetySummary) {
    bullet("•", line);
  }
  console.log("");
  console.error("NO PRODUCTION INBOX WRITE PERFORMED. Execute requires every gate above.");
  process.exit(1);
}

if (result.blockedCount > 0) {
  console.error("Delivery stopped with blocked unit(s).");
  for (const unit of result.unitResults) {
    if (unit.status === "blocked") {
      console.error(`  ${unit.unitKey}: [${unit.blockCode}] ${unit.blockMessage}`);
    }
  }
  process.exit(1);
}

console.log("Production inbox delivery recorded in control plane. Vamo apply is separate.");
bullet("delivery audit id", result.deliveryAuditId ?? "(none)");
bullet("idempotent replay", String(result.idempotentReplay));
for (const unit of result.unitResults) {
  if (unit.status === "delivered" || unit.status === "skipped") {
    bullet(`${unit.unitKey} package`, unit.packageId);
    bullet(`${unit.unitKey} checksum`, unit.checksum || "(replay)");
  }
}
