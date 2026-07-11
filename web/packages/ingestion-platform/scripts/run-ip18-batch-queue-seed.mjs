#!/usr/bin/env node

// IP-18.2 batch queue seed generator / optional executor.
//
// Default mode writes a self-contained SQL seed (no live DB required).
// Execution requires CONFIRM_CONFLUENDO_BATCH_QUEUE_SEED=YES and a control DSN.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed -- --spec path/to/batch.yaml
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed -- --full-data --preview
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed -- --full-data --include-empty-units
//   CONFIRM_CONFLUENDO_BATCH_QUEUE_SEED=YES INGESTION_CONTROL_DATABASE_URL=... npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed -- --execute

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { parseBatchPlanSpec } from "../dist/core/src/batch-plan-spec.js";
import { buildBatchFullDataPlanPreview } from "../dist/core/src/batch-full-data-plan-preview.js";
import { buildBatchPlan } from "../dist/core/src/batch-planner.js";
import { buildBatchQueueSnapshotFromPlan } from "../dist/core/src/batch-queue-read-model.js";
import {
  applySnapshotSupplyToQueueSnapshot,
  buildBatchSnapshotSupplyPreview,
  readSnapshotSourceRowsFromSpec
} from "../dist/core/src/batch-snapshot-supply-preview.js";
import { mapSnapshotToPersistenceBundle } from "../dist/core/src/batch-queue-persistence.js";
import { persistBatchQueueSnapshot } from "../dist/core/src/batch-queue-control.js";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const repoRoot = resolve(scriptDir, "../../../..");
const defaultSpecPath = resolve(packageRoot, "fixtures/platform/ip18/vamo-eu-poi-batch.yaml");
const fullDataSpecPath = resolve(packageRoot, "fixtures/platform/ip18/vamo-eu-full-data-batch.yaml");

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

const useFullData = hasFlag("--full-data");
const specPath = resolve(readArg("--spec", useFullData ? fullDataSpecPath : defaultSpecPath));
const writePath = readArg("--write", null);
const execute = hasFlag("--execute");
const previewOnly = hasFlag("--preview");
const includeEmptyUnits = hasFlag("--include-empty-units");

const raw = readFileSync(specPath, "utf8");
const parsed = parseBatchPlanSpec(raw);
if (!parsed.ok) {
  console.error("Batch spec validation failed:", parsed.errors);
  process.exit(1);
}

const plan = buildBatchPlan({ spec: parsed.spec });
const snapshotSourceRows = readSnapshotSourceRowsFromSpec(parsed.spec, packageRoot);
let snapshot = buildBatchQueueSnapshotFromPlan(plan);
let supplyPreview = null;

if (snapshotSourceRows) {
  supplyPreview = buildBatchSnapshotSupplyPreview({
    plan,
    spec: parsed.spec,
    rows: snapshotSourceRows
  });
  snapshot = applySnapshotSupplyToQueueSnapshot({
    snapshot,
    supplyPreview,
    seedMode: includeEmptyUnits ? "include_empty_units" : "block_empty_units"
  });
}

const preview = buildBatchFullDataPlanPreview({
  spec: parsed.spec,
  plan,
  snapshotSourceRows
});

if (previewOnly) {
  console.log("IP-18 batch queue preview (no writes)");
  console.log(`- spec: ${specPath}`);
  console.log(`- plan id: ${preview.planId}`);
  console.log(`- target: ${preview.targetKey} (${preview.targetEnvironment})`);
  console.log(`- source: ${preview.sourceKey}`);
  console.log(`- queue units: ${preview.queueUnitCount}`);
  console.log(`- planned: ${preview.plannedUnits}`);
  console.log(`- blocked: ${snapshot.progress.blocked}`);
  console.log(`- ready: ${snapshot.progress.ready}`);
  console.log(`- projected source candidates: ${preview.volume.totalSourceCandidates}`);
  console.log(`- projected expected target writes: ${preview.volume.totalExpectedTargetWrites}`);
  if (preview.snapshotSupply && supplyPreview) {
    console.log(`- actual snapshot rows available now: ${preview.snapshotSupply.actualSourceRows}`);
    console.log(
      `- planned units with matching snapshot rows: ${preview.snapshotSupply.unitsWithSourceRows}`
    );
    console.log(
      `- planned units without matching snapshot rows: ${preview.snapshotSupply.unitsWithoutSourceRows}`
    );
    console.log(`- source rows by country: ${JSON.stringify(supplyPreview.summary.rowsByCountry)}`);
    console.log(`- source rows by POI type: ${JSON.stringify(supplyPreview.summary.rowsByCategory)}`);
    console.log(
      `- default seed mode: ${includeEmptyUnits ? "include_empty_units" : supplyPreview.defaultSeedMode}`
    );
    console.log(
      `- default seed blocks empty units: ${includeEmptyUnits ? "no" : "yes"} (${supplyPreview.defaultSeedBlockReason})`
    );
    console.log("");
    console.log(`First ${Math.min(8, supplyPreview.supplyReadyUnits.length)} supply-ready units:`);
    for (const unit of supplyPreview.supplyReadyUnits.slice(0, 8)) {
      console.log(`  ${unit.unitKey} · ${unit.validSourceRowCount} row(s)`);
    }
    if (supplyPreview.emptyUnits.length > 0) {
      console.log("");
      console.log(`First ${Math.min(8, supplyPreview.emptyUnits.length)} empty units:`);
      for (const unit of supplyPreview.emptyUnits.slice(0, 8)) {
        console.log(`  ${unit.unitKey} · ${supplyPreview.defaultSeedBlockReason}`);
      }
    }
  }
  console.log(`- coverage matrix countries: ${Object.keys(preview.coverageMatrix).length}`);
  console.log(`- next action: ${snapshot.nextAction}`);
  process.exit(0);
}

const bundle = mapSnapshotToPersistenceBundle(snapshot, parsed.spec);
const sql = renderSeedSql(bundle, parsed.spec.id);

if (execute) {
  if (process.env.CONFIRM_CONFLUENDO_BATCH_QUEUE_SEED !== "YES") {
    console.error(
      "Refusing to execute without CONFIRM_CONFLUENDO_BATCH_QUEUE_SEED=YES."
    );
    process.exit(1);
  }
  const dsn = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  if (!dsn) {
    console.error("INGESTION_CONTROL_DATABASE_URL is required for --execute.");
    process.exit(1);
  }
  const result = await persistBatchQueueSnapshot({
    connectionString: dsn,
    projectKey: snapshot.projectKey,
    snapshot,
    spec: parsed.spec
  });
  console.log(`Persisted batch queue plan id=${result.batchPlanId} for project=${snapshot.projectKey}.`);
  process.exit(0);
}

const defaultWritePath = resolve(
  repoRoot,
  useFullData || parsed.spec.id.includes("full-data")
    ? "docs/platform/ingestion/bootstrap/sql/ip18_vamo_full_data_batch_queue_seed.sql"
    : "docs/platform/ingestion/bootstrap/sql/ip18_vamo_batch_queue_seed.sql"
);
const outputPath = writePath ? resolve(writePath) : defaultWritePath;

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, sql, "utf8");
console.log(`Wrote batch queue seed SQL to ${outputPath}`);
if (supplyPreview) {
  console.log(
    `- seeded with supply binding: ${includeEmptyUnits ? "include_empty_units" : supplyPreview.defaultSeedMode}`
  );
  console.log(`- blocked empty units: ${snapshot.progress.blocked}`);
  console.log(`- supply-ready units: ${supplyPreview.summary.unitsWithSourceRows}`);
}

function renderSeedSql(bundle, planId) {
  const specJson = sqlLiteral(JSON.stringify(bundle.plan.spec));
  const summaryJson = sqlLiteral(JSON.stringify(bundle.plan.planSummary));
  const itemInserts = bundle.items
    .map((item) => {
      return `  select
    bp.id,
    ${sqlLiteral(item.unitKey)},
    ${sqlLiteral(item.countryCode)},
    ${sqlLiteral(item.geographyKey)},
    ${sqlLiteral(item.geographyLabel)},
    ${sqlLiteral(item.geographyKind)},
    ${sqlLiteral(item.category)},
    ${sqlLiteral(item.sourceKey)},
    ${sqlLiteral(item.targetKey)},
    ${sqlLiteral(item.targetEnvironment)},
    ${sqlLiteral(item.status)},
    ${item.priority},
    ${item.runOrder},
    ${sqlLiteral(JSON.stringify(item.blockers))}::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = ${sqlLiteral(bundle.plan.planKey)}
  where p.project_key = 'vamo'`;
    })
    .join("\n  union all\n");

  return `-- IP-18.2 / IP-18.8 — Vamo batch queue seed (${planId}, Confluendo control-plane only).
--
-- Purpose: persist the bundled Vamo batch queue into the control plane so
-- /admin/ingestion can show LIVE queue state. No provider calls and no Vamo
-- staging/production writes.
--
-- Run as the DB OWNER after control_schema.sql and control_bootstrap_confluendo.sql.
-- Idempotent: re-running upserts the same plan and queue items.

begin;

do $$
begin
  if not exists (select 1 from ingestion_platform.ingestion_projects where project_key = 'vamo') then
    raise exception 'Project project_key=''vamo'' not found. Run control_bootstrap_confluendo.sql first.';
  end if;
end $$;

insert into ingestion_platform.ingestion_batch_plans (
  project_id,
  plan_key,
  source_key,
  target_key,
  target_environment,
  safety_mode,
  spec,
  plan_summary,
  status
)
select
  p.id,
  ${sqlLiteral(bundle.plan.planKey)},
  ${sqlLiteral(bundle.plan.sourceKey)},
  ${sqlLiteral(bundle.plan.targetKey)},
  ${sqlLiteral(bundle.plan.targetEnvironment)},
  ${sqlLiteral(bundle.plan.safetyMode)},
  ${specJson}::jsonb,
  ${summaryJson}::jsonb,
  ${sqlLiteral(bundle.plan.status)}
from ingestion_platform.ingestion_projects p
where p.project_key = 'vamo'
on conflict (project_id, plan_key) do update
  set source_key = excluded.source_key,
      target_key = excluded.target_key,
      target_environment = excluded.target_environment,
      safety_mode = excluded.safety_mode,
      spec = excluded.spec,
      plan_summary = excluded.plan_summary,
      status = excluded.status,
      updated_at = now();

insert into ingestion_platform.ingestion_batch_queue_items (
  batch_plan_id,
  unit_key,
  country_code,
  geography_key,
  geography_label,
  geography_kind,
  category,
  source_key,
  target_key,
  target_environment,
  status,
  priority,
  run_order,
  blockers,
  proposal,
  run_report
)
${itemInserts}
on conflict (batch_plan_id, unit_key) do update
  set country_code = excluded.country_code,
      geography_key = excluded.geography_key,
      geography_label = excluded.geography_label,
      geography_kind = excluded.geography_kind,
      category = excluded.category,
      source_key = excluded.source_key,
      target_key = excluded.target_key,
      target_environment = excluded.target_environment,
      status = excluded.status,
      priority = excluded.priority,
      run_order = excluded.run_order,
      blockers = excluded.blockers,
      proposal = excluded.proposal,
      run_report = excluded.run_report,
      updated_at = now();

commit;
`;
}

function sqlLiteral(value) {
  if (value === null || value === undefined) {
    return "null";
  }
  return `'${String(value).replace(/'/g, "''")}'`;
}
