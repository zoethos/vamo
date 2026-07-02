#!/usr/bin/env node

// IP-18.2 batch queue seed generator / optional executor.
//
// Default mode writes a self-contained SQL seed (no live DB required).
// Execution requires CONFIRM_CONFLUENDO_BATCH_QUEUE_SEED=YES and a control DSN.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed
//   CONFIRM_CONFLUENDO_BATCH_QUEUE_SEED=YES INGESTION_CONTROL_DATABASE_URL=... npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed -- --execute

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { parseBatchPlanSpec } from "../dist/core/src/batch-plan-spec.js";
import { sampleVamoEuPoiBatchYaml } from "../dist/core/src/batch-plan-read-model.js";
import { sampleVamoEuPoiBatchQueueSnapshot } from "../dist/core/src/batch-queue-read-model.js";
import { mapSnapshotToPersistenceBundle } from "../dist/core/src/batch-queue-persistence.js";
import { persistBatchQueueSnapshot } from "../dist/core/src/batch-queue-control.js";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "../../../..");

function readArg(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  return fallback;
}

const writePath = readArg("--write", null);
const execute = process.argv.includes("--execute");
const parsed = parseBatchPlanSpec(sampleVamoEuPoiBatchYaml());
if (!parsed.ok) {
  console.error("Sample batch spec invalid:", parsed.errors);
  process.exit(1);
}

const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
const bundle = mapSnapshotToPersistenceBundle(snapshot, parsed.spec);
const sql = renderSeedSql(bundle);

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
  "docs/platform/ingestion/bootstrap/sql/ip18_vamo_batch_queue_seed.sql"
);
const outputPath = writePath ? resolve(writePath) : defaultWritePath;

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, sql, "utf8");
console.log(`Wrote batch queue seed SQL to ${outputPath}`);

function renderSeedSql(bundle) {
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

  return `-- IP-18.2 — Vamo EU POI batch queue seed (Confluendo control-plane only).
--
-- Purpose: persist the bundled IP-18 Vamo EU POI batch queue into the control
-- plane so /admin/ingestion can show LIVE queue state. No provider calls and
-- no Vamo staging/production writes.
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
