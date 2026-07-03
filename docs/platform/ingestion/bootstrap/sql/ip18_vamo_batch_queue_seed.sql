-- IP-18.2 — Vamo EU POI batch queue seed (Confluendo control-plane only).
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
  'vamo-eu-poi-sample',
  'fsq-os-places-sample',
  'vamo-place-intelligence',
  'staging',
  'dry_run',
  '{"kind":"ingestion.batch_plan","version":1,"id":"vamo-eu-poi-sample","projectKey":"vamo","sourceKey":"fsq-os-places-sample","targetProfileKey":"place-intelligence","targetKey":"vamo-place-intelligence","targetEnvironment":"staging","safetyMode":"dry_run","geographies":{"countries":[{"key":"italy","label":"Italy"},{"key":"france","label":"France"},{"key":"germany","label":"Germany"},{"key":"spain","label":"Spain"}],"regions":[{"key":"lombardy-italy","label":"Lombardy","country":"italy"}],"cities":[{"key":"rome-italy","label":"Rome","country":"italy"},{"key":"paris-france","label":"Paris","country":"france"},{"key":"munich-germany","label":"Munich","country":"germany"},{"key":"barcelona-spain","label":"Barcelona","country":"spain"}]},"categories":["landmark","poi","restaurant","transport"],"priorityHints":[{"geography":"rome-italy","category":"poi","weight":10},{"geography":"paris-france","category":"landmark","weight":8}],"bounds":{"sampleRowLimitPerUnit":50,"defaultBatchSize":10},"notes":"Representative EU POI batch sample for IP-18 planning only. Full EU coverage will come from open-source snapshots such as FSQ OS Places, GeoNames, and Wikidata in later slices — not from this tiny fixture."}'::jsonb,
  '{"queueId":"vamo-eu-poi-sample-queue","projectKey":"vamo","nextAction":"Review batch queue (36 ready for dry-run) and approve scheduling.","progress":{"total":36,"planned":0,"blocked":0,"ready":36,"applied":0,"execution":{"dryRunReady":0,"dryRunRunning":0,"dryRunSucceeded":0,"dryRunBlocked":0},"stagingCanary":{"dryRunSucceededEligible":0,"ready":0,"approved":0,"running":0,"succeeded":0,"blocked":0}},"coverage":{"perCountry":{"italy":12,"france":8,"spain":8,"germany":8},"perCategory":{"poi":9,"landmark":9,"restaurant":9,"transport":9},"perSource":{"fsq-os-places-sample":36},"matrix":{"italy":{"poi":3,"landmark":3,"restaurant":3,"transport":3},"france":{"landmark":2,"poi":2,"restaurant":2,"transport":2},"spain":{"landmark":2,"poi":2,"restaurant":2,"transport":2},"germany":{"landmark":2,"poi":2,"restaurant":2,"transport":2}}},"blockerSummaries":[]}'::jsonb,
  'active'
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
  select
    bp.id,
    'vamo-place-intelligence:rome-italy:poi',
    'italy',
    'rome-italy',
    'rome-italy',
    'city',
    'poi',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    10,
    1,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:paris-france:landmark',
    'france',
    'paris-france',
    'paris-france',
    'city',
    'landmark',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    8,
    2,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:barcelona-spain:landmark',
    'spain',
    'barcelona-spain',
    'barcelona-spain',
    'city',
    'landmark',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    3,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:barcelona-spain:poi',
    'spain',
    'barcelona-spain',
    'barcelona-spain',
    'city',
    'poi',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    4,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:barcelona-spain:restaurant',
    'spain',
    'barcelona-spain',
    'barcelona-spain',
    'city',
    'restaurant',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    5,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:barcelona-spain:transport',
    'spain',
    'barcelona-spain',
    'barcelona-spain',
    'city',
    'transport',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    6,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:france:landmark',
    'france',
    'france',
    'france',
    'country',
    'landmark',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    7,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:france:poi',
    'france',
    'france',
    'france',
    'country',
    'poi',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    8,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:france:restaurant',
    'france',
    'france',
    'france',
    'country',
    'restaurant',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    9,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:france:transport',
    'france',
    'france',
    'france',
    'country',
    'transport',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    10,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:germany:landmark',
    'germany',
    'germany',
    'germany',
    'country',
    'landmark',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    11,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:germany:poi',
    'germany',
    'germany',
    'germany',
    'country',
    'poi',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    12,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:germany:restaurant',
    'germany',
    'germany',
    'germany',
    'country',
    'restaurant',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    13,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:germany:transport',
    'germany',
    'germany',
    'germany',
    'country',
    'transport',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    14,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:italy:landmark',
    'italy',
    'italy',
    'italy',
    'country',
    'landmark',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    15,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:italy:poi',
    'italy',
    'italy',
    'italy',
    'country',
    'poi',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    16,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:italy:restaurant',
    'italy',
    'italy',
    'italy',
    'country',
    'restaurant',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    17,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:italy:transport',
    'italy',
    'italy',
    'italy',
    'country',
    'transport',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    18,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:lombardy-italy:landmark',
    'italy',
    'lombardy-italy',
    'lombardy-italy',
    'region',
    'landmark',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    19,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:lombardy-italy:poi',
    'italy',
    'lombardy-italy',
    'lombardy-italy',
    'region',
    'poi',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    20,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:lombardy-italy:restaurant',
    'italy',
    'lombardy-italy',
    'lombardy-italy',
    'region',
    'restaurant',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    21,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:lombardy-italy:transport',
    'italy',
    'lombardy-italy',
    'lombardy-italy',
    'region',
    'transport',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    22,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:munich-germany:landmark',
    'germany',
    'munich-germany',
    'munich-germany',
    'city',
    'landmark',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    23,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:munich-germany:poi',
    'germany',
    'munich-germany',
    'munich-germany',
    'city',
    'poi',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    24,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:munich-germany:restaurant',
    'germany',
    'munich-germany',
    'munich-germany',
    'city',
    'restaurant',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    25,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:munich-germany:transport',
    'germany',
    'munich-germany',
    'munich-germany',
    'city',
    'transport',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    26,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:paris-france:poi',
    'france',
    'paris-france',
    'paris-france',
    'city',
    'poi',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    27,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:paris-france:restaurant',
    'france',
    'paris-france',
    'paris-france',
    'city',
    'restaurant',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    28,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:paris-france:transport',
    'france',
    'paris-france',
    'paris-france',
    'city',
    'transport',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    29,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:rome-italy:landmark',
    'italy',
    'rome-italy',
    'rome-italy',
    'city',
    'landmark',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    30,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:rome-italy:restaurant',
    'italy',
    'rome-italy',
    'rome-italy',
    'city',
    'restaurant',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    31,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:rome-italy:transport',
    'italy',
    'rome-italy',
    'rome-italy',
    'city',
    'transport',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    32,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:spain:landmark',
    'spain',
    'spain',
    'spain',
    'country',
    'landmark',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    33,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:spain:poi',
    'spain',
    'spain',
    'spain',
    'country',
    'poi',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    34,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:spain:restaurant',
    'spain',
    'spain',
    'spain',
    'country',
    'restaurant',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    35,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
  union all
  select
    bp.id,
    'vamo-place-intelligence:spain:transport',
    'spain',
    'spain',
    'spain',
    'country',
    'transport',
    'fsq-os-places-sample',
    'vamo-place-intelligence',
    'staging',
    'ready_for_dry_run',
    0,
    36,
    '[]'::jsonb,
    null::jsonb,
    null::jsonb
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp
    on bp.project_id = p.id
   and bp.plan_key = 'vamo-eu-poi-sample'
  where p.project_key = 'vamo'
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
