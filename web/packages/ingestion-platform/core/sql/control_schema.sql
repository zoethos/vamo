begin;

create schema if not exists ingestion_platform;

create table if not exists ingestion_platform.ingestion_projects (
  id bigint generated always as identity primary key,
  project_key text not null,
  display_name text not null,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_projects_project_key_unique unique (project_key),
  constraint ingestion_projects_project_key_format check (
    project_key ~ '^[a-z0-9][a-z0-9_:-]*$'
  ),
  constraint ingestion_projects_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  )
);

create table if not exists ingestion_platform.ingestion_admin_principals (
  provider text not null default 'supabase',
  provider_user_id text not null,
  email text not null,
  role text not null,
  scopes text[] not null,
  mfa_required boolean not null default true,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  created_by_provider text,
  created_by_provider_user_id text,
  expires_at timestamptz,
  last_seen_at timestamptz,
  constraint ingestion_admin_principals_pk primary key (provider, provider_user_id),
  constraint ingestion_admin_principals_provider_check check (
    provider ~ '^[a-z0-9][a-z0-9_:-]*$'
  ),
  constraint ingestion_admin_principals_email_nonempty check (
    length(btrim(email)) > 0
  ),
  constraint ingestion_admin_principals_role_check check (
    role in ('viewer', 'operator', 'admin')
  ),
  constraint ingestion_admin_principals_status_check check (
    status in ('active', 'suspended')
  ),
  constraint ingestion_admin_principals_scopes_nonempty check (
    array_length(scopes, 1) is not null
  )
);

create table if not exists ingestion_platform.ingestion_specs (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  spec_key text not null,
  spec_kind text not null,
  revision bigint not null,
  content jsonb not null,
  content_sha256 text not null,
  status text not null default 'draft',
  created_by text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_specs_revision_positive check (revision > 0),
  constraint ingestion_specs_kind_check check (
    spec_kind in ('pipeline', 'target', 'source', 'profile')
  ),
  constraint ingestion_specs_status_check check (
    status in ('draft', 'active', 'archived')
  ),
  constraint ingestion_specs_content_object check (
    jsonb_typeof(content) = 'object'
  ),
  constraint ingestion_specs_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  ),
  constraint ingestion_specs_revision_unique unique (project_id, spec_key, revision)
);

create table if not exists ingestion_platform.ingestion_sources (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  source_key text not null,
  display_name text not null,
  adapter text not null,
  policy jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_sources_policy_object check (
    jsonb_typeof(policy) = 'object'
  ),
  constraint ingestion_sources_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  ),
  constraint ingestion_sources_source_key_unique unique (project_id, source_key)
);

create table if not exists ingestion_platform.ingestion_targets (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  target_key text not null,
  display_name text not null,
  adapter text not null,
  safety_mode text not null default 'dry_run',
  policy jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_targets_safety_mode_check check (
    safety_mode in ('dry_run', 'approved_write')
  ),
  constraint ingestion_targets_policy_object check (
    jsonb_typeof(policy) = 'object'
  ),
  constraint ingestion_targets_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  ),
  constraint ingestion_targets_target_key_unique unique (project_id, target_key)
);

create table if not exists ingestion_platform.ingestion_runs (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  spec_id bigint not null references ingestion_platform.ingestion_specs(id) on delete restrict,
  run_key text not null,
  status text not null default 'queued',
  trigger_type text not null default 'manual',
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint ingestion_runs_status_check check (
    status in ('queued', 'running', 'paused', 'succeeded', 'failed', 'cancelled')
  ),
  constraint ingestion_runs_summary_object check (
    jsonb_typeof(summary) = 'object'
  ),
  constraint ingestion_runs_run_key_unique unique (project_id, run_key)
);

create table if not exists ingestion_platform.ingestion_tasks (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  run_id bigint not null references ingestion_platform.ingestion_runs(id) on delete cascade,
  source_id bigint references ingestion_platform.ingestion_sources(id) on delete set null,
  target_id bigint references ingestion_platform.ingestion_targets(id) on delete set null,
  task_key text not null,
  status text not null default 'queued',
  priority integer not null default 0,
  attempt_count integer not null default 0,
  checkpoint_scope text,
  input jsonb not null default '{}'::jsonb,
  error_code text,
  error_message text,
  next_attempt_at timestamptz,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint ingestion_tasks_status_check check (
    status in ('queued', 'running', 'paused', 'succeeded', 'failed', 'blocked', 'cancelled')
  ),
  constraint ingestion_tasks_attempt_count_nonnegative check (attempt_count >= 0),
  constraint ingestion_tasks_input_object check (
    jsonb_typeof(input) = 'object'
  ),
  constraint ingestion_tasks_task_key_unique unique (run_id, task_key)
);

create table if not exists ingestion_platform.ingestion_worker_leases (
  id bigint generated always as identity primary key,
  task_id bigint not null references ingestion_platform.ingestion_tasks(id) on delete cascade,
  worker_id text not null,
  lease_token text not null,
  status text not null default 'active',
  acquired_at timestamptz not null default now(),
  heartbeat_at timestamptz not null default now(),
  expires_at timestamptz not null,
  released_at timestamptz,
  release_reason text,
  constraint ingestion_worker_leases_status_check check (
    status in ('active', 'released', 'expired')
  ),
  constraint ingestion_worker_leases_lease_token_unique unique (lease_token)
);

create table if not exists ingestion_platform.ingestion_checkpoints (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  pipeline_spec_id bigint not null references ingestion_platform.ingestion_specs(id) on delete restrict,
  source_id bigint not null references ingestion_platform.ingestion_sources(id) on delete cascade,
  target_id bigint not null references ingestion_platform.ingestion_targets(id) on delete cascade,
  cursor_scope text not null,
  cursor_strategy text not null,
  cursor_value jsonb not null,
  last_record_key text,
  updated_by_run_id bigint references ingestion_platform.ingestion_runs(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_checkpoints_cursor_strategy_check check (
    cursor_strategy in ('monotonic_row_id', 'page_token', 'offset', 'snapshot')
  ),
  constraint ingestion_checkpoints_cursor_value_object check (
    jsonb_typeof(cursor_value) = 'object'
  ),
  constraint ingestion_checkpoints_scope_unique unique (
    project_id,
    pipeline_spec_id,
    source_id,
    target_id,
    cursor_scope
  )
);

create table if not exists ingestion_platform.ingestion_events (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  run_id bigint references ingestion_platform.ingestion_runs(id) on delete set null,
  task_id bigint references ingestion_platform.ingestion_tasks(id) on delete set null,
  event_type text not null,
  severity text not null default 'info',
  signal text,
  message text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint ingestion_events_severity_check check (
    severity in ('debug', 'info', 'warn', 'error')
  ),
  constraint ingestion_events_payload_object check (
    jsonb_typeof(payload) = 'object'
  )
);

create table if not exists ingestion_platform.ingestion_dead_letters (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  run_id bigint references ingestion_platform.ingestion_runs(id) on delete set null,
  task_id bigint references ingestion_platform.ingestion_tasks(id) on delete set null,
  source_id bigint references ingestion_platform.ingestion_sources(id) on delete set null,
  record_identity text,
  reason_code text not null,
  reason_message text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolution_note text,
  constraint ingestion_dead_letters_payload_object check (
    jsonb_typeof(payload) = 'object'
  )
);

create table if not exists ingestion_platform.ingestion_artifacts (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  run_id bigint references ingestion_platform.ingestion_runs(id) on delete set null,
  task_id bigint references ingestion_platform.ingestion_tasks(id) on delete set null,
  artifact_type text not null,
  uri text not null,
  content_sha256 text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint ingestion_artifacts_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  )
);

create table if not exists ingestion_platform.ingestion_policy_evaluations (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  run_id bigint references ingestion_platform.ingestion_runs(id) on delete set null,
  task_id bigint references ingestion_platform.ingestion_tasks(id) on delete set null,
  source_id bigint references ingestion_platform.ingestion_sources(id) on delete set null,
  policy_key text not null,
  decision text not null,
  reason_code text,
  subject_key text,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint ingestion_policy_evaluations_decision_check check (
    decision in ('allow', 'deny', 'review')
  ),
  constraint ingestion_policy_evaluations_evidence_object check (
    jsonb_typeof(evidence) = 'object'
  )
);

create table if not exists ingestion_platform.ingestion_promotions (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  candidate_key text not null,
  promotion_scope text not null,
  status text not null default 'pending_review',
  source_evaluation_id bigint references ingestion_platform.ingestion_policy_evaluations(id) on delete set null,
  decision_reason text,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  constraint ingestion_promotions_scope_check check (
    promotion_scope in ('project', 'global')
  ),
  constraint ingestion_promotions_status_check check (
    status in ('pending_review', 'promoted', 'rejected')
  ),
  constraint ingestion_promotions_candidate_scope_unique unique (
    project_id,
    candidate_key,
    promotion_scope
  )
);

create table if not exists ingestion_platform.ingestion_shipments (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  run_id bigint references ingestion_platform.ingestion_runs(id) on delete set null,
  target_id bigint not null references ingestion_platform.ingestion_targets(id) on delete restrict,
  shipment_key text not null,
  mode text not null default 'dry_run',
  status text not null default 'planned',
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  planned_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint ingestion_shipments_mode_check check (
    mode in ('dry_run', 'approved_write')
  ),
  constraint ingestion_shipments_status_check check (
    status in ('planned', 'dry_run', 'approved', 'shipping', 'succeeded', 'failed', 'cancelled')
  ),
  constraint ingestion_shipments_summary_object check (
    jsonb_typeof(summary) = 'object'
  ),
  constraint ingestion_shipments_shipment_key_unique unique (project_id, shipment_key)
);

create table if not exists ingestion_platform.ingestion_shipment_items (
  id bigint generated always as identity primary key,
  shipment_id bigint not null references ingestion_platform.ingestion_shipments(id) on delete cascade,
  target_table text not null,
  operation text not null,
  idempotency_key text not null,
  record_key text not null,
  checksum text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  applied_at timestamptz,
  constraint ingestion_shipment_items_operation_check check (
    operation in ('insert', 'update', 'delete', 'no_op')
  ),
  constraint ingestion_shipment_items_status_check check (
    status in ('pending', 'applied', 'failed', 'skipped')
  ),
  constraint ingestion_shipment_items_payload_object check (
    jsonb_typeof(payload) = 'object'
  ),
  constraint ingestion_shipment_items_idempotency_unique unique (
    shipment_id,
    idempotency_key
  )
);

create table if not exists ingestion_platform.ingestion_audit_log (
  id bigint generated always as identity primary key,
  project_id bigint references ingestion_platform.ingestion_projects(id) on delete set null,
  actor_type text not null,
  actor_id text,
  action text not null,
  target_type text not null,
  target_id text,
  reason text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint ingestion_audit_log_actor_type_check check (
    actor_type in ('operator', 'system', 'worker', 'api', 'autonomous_agent')
  ),
  constraint ingestion_audit_log_payload_object check (
    jsonb_typeof(payload) = 'object'
  )
);

alter table ingestion_platform.ingestion_audit_log
  drop constraint if exists ingestion_audit_log_actor_type_check;

alter table ingestion_platform.ingestion_audit_log
  add constraint ingestion_audit_log_actor_type_check check (
    actor_type in ('operator', 'system', 'worker', 'api', 'autonomous_agent')
  );

-- Progressive scheduling backlog: one row per target candidate/proposal. Stores
-- the deterministic scorecard, the bounded schedule proposal, and the latest
-- progressive dry-run report as JSONB produced by platform-core policy. This is
-- a read surface for the dashboard; no scheduling mutation path writes it yet.
create table if not exists ingestion_platform.ingestion_schedule_proposals (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  target_key text not null,
  source_key text,
  work_status text not null default 'proposed',
  tier text not null,
  safety_mode text not null default 'dry_run',
  scorecard jsonb not null,
  proposal jsonb,
  run_report jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_schedule_proposals_work_status_check check (
    work_status in ('proposed', 'scheduled', 'running', 'review_required', 'blocked')
  ),
  constraint ingestion_schedule_proposals_safety_mode_check check (
    safety_mode in ('dry_run', 'staging_write', 'production_write')
  ),
  constraint ingestion_schedule_proposals_scorecard_object check (
    jsonb_typeof(scorecard) = 'object'
  ),
  constraint ingestion_schedule_proposals_proposal_object check (
    proposal is null or jsonb_typeof(proposal) = 'object'
  ),
  constraint ingestion_schedule_proposals_run_report_object check (
    run_report is null or jsonb_typeof(run_report) = 'object'
  ),
  constraint ingestion_schedule_proposals_target_key_unique unique (project_id, target_key)
);

create table if not exists ingestion_platform.ingestion_batch_plans (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  plan_key text not null,
  source_key text not null,
  target_key text not null,
  target_environment text not null,
  safety_mode text not null default 'dry_run',
  spec jsonb not null,
  plan_summary jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_batch_plans_plan_key_unique unique (project_id, plan_key),
  constraint ingestion_batch_plans_target_environment_check check (
    target_environment in ('staging', 'production')
  ),
  constraint ingestion_batch_plans_safety_mode_check check (
    safety_mode = 'dry_run'
  ),
  constraint ingestion_batch_plans_status_check check (
    status in ('active', 'archived')
  ),
  constraint ingestion_batch_plans_spec_object check (
    jsonb_typeof(spec) = 'object'
  ),
  constraint ingestion_batch_plans_plan_summary_object check (
    jsonb_typeof(plan_summary) = 'object'
  )
);

create table if not exists ingestion_platform.ingestion_batch_queue_items (
  id bigint generated always as identity primary key,
  batch_plan_id bigint not null references ingestion_platform.ingestion_batch_plans(id) on delete cascade,
  unit_key text not null,
  country_code text not null,
  geography_key text not null,
  geography_label text,
  geography_kind text not null,
  category text not null,
  source_key text not null,
  target_key text not null,
  target_environment text not null,
  status text not null,
  priority integer not null default 0,
  run_order integer not null,
  blockers jsonb not null default '[]'::jsonb,
  proposal jsonb,
  run_report jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_batch_queue_items_unit_key_unique unique (batch_plan_id, unit_key),
  constraint ingestion_batch_queue_items_target_environment_check check (
    target_environment in ('staging', 'production')
  ),
  constraint ingestion_batch_queue_items_status_check check (
    status in (
      'planned',
      'blocked',
      'ready_for_dry_run',
      'dry_run_ready',
      'staged_ready',
      'production_ready',
      'applied'
    )
  ),
  constraint ingestion_batch_queue_items_blockers_array check (
    jsonb_typeof(blockers) = 'array'
  ),
  constraint ingestion_batch_queue_items_proposal_object check (
    proposal is null or jsonb_typeof(proposal) = 'object'
  ),
  constraint ingestion_batch_queue_items_run_report_object check (
    run_report is null or jsonb_typeof(run_report) = 'object'
  )
);

create table if not exists ingestion_platform.ingestion_batch_dry_run_executions (
  id bigint generated always as identity primary key,
  batch_plan_id bigint not null references ingestion_platform.ingestion_batch_plans(id) on delete cascade,
  execution_key text not null,
  target_key text not null,
  target_environment text not null,
  max_units integer not null,
  audit_id text,
  audit_reason text not null,
  actor_type text not null,
  actor_id text not null,
  status text not null default 'running',
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint ingestion_batch_dry_run_executions_execution_key_unique unique (batch_plan_id, execution_key),
  constraint ingestion_batch_dry_run_executions_target_environment_check check (
    target_environment in ('staging', 'production')
  ),
  constraint ingestion_batch_dry_run_executions_status_check check (
    status in ('running', 'succeeded', 'partial', 'failed')
  ),
  constraint ingestion_batch_dry_run_executions_max_units_positive check (max_units > 0),
  constraint ingestion_batch_dry_run_executions_summary_object check (
    jsonb_typeof(summary) = 'object'
  )
);

alter table ingestion_platform.ingestion_batch_queue_items
  drop constraint if exists ingestion_batch_queue_items_status_check;

alter table ingestion_platform.ingestion_batch_queue_items
  add constraint ingestion_batch_queue_items_status_check check (
    status in (
      'planned',
      'blocked',
      'ready_for_dry_run',
      'dry_run_ready',
      'dry_run_running',
      'dry_run_succeeded',
      'dry_run_blocked',
      'staging_canary_ready',
      'staging_canary_approved',
      'staging_canary_running',
      'staging_canary_succeeded',
      'staging_canary_blocked',
      'staged_ready',
      'production_ready',
      'applied',
      'production_package_ready',
      'production_package_approved',
      'production_package_delivering',
      'production_package_delivered',
      'consumer_apply_pending',
      'consumer_applied',
      'consumer_apply_failed',
      'production_package_blocked'
    )
  );

create table if not exists ingestion_platform.ingestion_batch_canary_waves (
  id bigint generated always as identity primary key,
  batch_plan_id bigint not null references ingestion_platform.ingestion_batch_plans(id) on delete cascade,
  wave_key text not null,
  target_key text not null,
  target_environment text not null,
  max_units integer not null,
  max_rows integer not null,
  audit_reason text not null,
  actor_type text not null,
  actor_id text not null,
  status text not null default 'approved',
  summary jsonb not null default '{}'::jsonb,
  approved_at timestamptz not null,
  approval_expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_batch_canary_waves_wave_key_unique unique (batch_plan_id, wave_key),
  constraint ingestion_batch_canary_waves_target_environment_check check (
    target_environment = 'staging'
  ),
  constraint ingestion_batch_canary_waves_status_check check (
    status in (
      'planned',
      'approval_pending',
      'approved',
      'running',
      'succeeded',
      'partial',
      'failed',
      'blocked'
    )
  ),
  constraint ingestion_batch_canary_waves_max_units_positive check (max_units > 0),
  constraint ingestion_batch_canary_waves_max_rows_positive check (max_rows > 0),
  constraint ingestion_batch_canary_waves_summary_object check (
    jsonb_typeof(summary) = 'object'
  )
);

create table if not exists ingestion_platform.ingestion_batch_canary_wave_items (
  id bigint generated always as identity primary key,
  wave_id bigint not null references ingestion_platform.ingestion_batch_canary_waves(id) on delete cascade,
  unit_key text not null,
  run_order integer not null,
  status text not null default 'approved',
  planned_row_count integer not null default 0,
  blockers jsonb not null default '[]'::jsonb,
  shipment_id bigint references ingestion_platform.ingestion_shipments(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_batch_canary_wave_items_unit_key_unique unique (wave_id, unit_key),
  constraint ingestion_batch_canary_wave_items_status_check check (
    status in ('approved', 'running', 'succeeded', 'blocked')
  ),
  constraint ingestion_batch_canary_wave_items_blockers_array check (
    jsonb_typeof(blockers) = 'array'
  ),
  constraint ingestion_batch_canary_wave_items_planned_row_count_nonnegative check (
    planned_row_count >= 0
  )
);

create table if not exists ingestion_platform.ingestion_batch_production_package_waves (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id),
  batch_plan_id bigint not null references ingestion_platform.ingestion_batch_plans(id) on delete cascade,
  wave_key text not null,
  target_key text not null,
  target_environment text not null,
  schema_contract text not null,
  max_units integer not null,
  max_rows integer not null,
  max_packages integer not null,
  approval_audit_id text,
  approval_reason text not null,
  approved_by jsonb not null default '{}'::jsonb,
  approved_at timestamptz not null,
  approval_expires_at timestamptz not null,
  actor_type text not null,
  actor_id text not null,
  status text not null default 'approved',
  package_id text,
  package_key text,
  package_checksum text,
  delivery_audit_id text,
  delivery_status text,
  consumer_apply_status text,
  consumer_apply_evidence jsonb,
  blockers jsonb not null default '[]'::jsonb,
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_batch_production_package_waves_wave_key_unique unique (batch_plan_id, wave_key),
  constraint ingestion_batch_production_package_waves_target_environment_check check (
    target_environment = 'production'
  ),
  constraint ingestion_batch_production_package_waves_status_check check (
    status in (
      'planned',
      'approval_pending',
      'approved',
      'delivering',
      'delivered',
      'expired',
      'consumer_apply_pending',
      'consumer_applied',
      'consumer_apply_failed',
      'blocked'
    )
  ),
  constraint ingestion_batch_production_package_waves_max_units_positive check (max_units > 0),
  constraint ingestion_batch_production_package_waves_max_rows_positive check (max_rows > 0),
  constraint ingestion_batch_production_package_waves_max_packages_positive check (max_packages > 0),
  constraint ingestion_batch_production_package_waves_blockers_array check (
    jsonb_typeof(blockers) = 'array'
  ),
  constraint ingestion_batch_production_package_waves_summary_object check (
    jsonb_typeof(summary) = 'object'
  ),
  constraint ingestion_batch_production_package_waves_approved_by_object check (
    jsonb_typeof(approved_by) = 'object'
  )
);

create table if not exists ingestion_platform.ingestion_batch_production_package_wave_items (
  id bigint generated always as identity primary key,
  wave_id bigint not null references ingestion_platform.ingestion_batch_production_package_waves(id) on delete cascade,
  queue_item_id bigint not null references ingestion_platform.ingestion_batch_queue_items(id),
  unit_key text not null,
  run_order integer not null,
  planned_row_count integer not null default 0,
  schema_contract text not null,
  package_key text,
  package_id text,
  dry_run_evidence jsonb not null default '{}'::jsonb,
  staging_evidence jsonb not null default '{}'::jsonb,
  status text not null default 'approved',
  checksum text,
  apply_evidence jsonb,
  blockers jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_batch_production_package_wave_items_unit_key_unique unique (wave_id, unit_key),
  constraint ingestion_batch_production_package_wave_items_status_check check (
    status in (
      'approved',
      'delivering',
      'delivered',
      'released',
      'consumer_apply_pending',
      'consumer_applied',
      'consumer_apply_failed',
      'blocked'
    )
  ),
  constraint ingestion_batch_production_package_wave_items_blockers_array check (
    jsonb_typeof(blockers) = 'array'
  ),
  constraint ingestion_batch_production_package_wave_items_dry_run_evidence_object check (
    jsonb_typeof(dry_run_evidence) = 'object'
  ),
  constraint ingestion_batch_production_package_wave_items_staging_evidence_object check (
    jsonb_typeof(staging_evidence) = 'object'
  ),
  constraint ingestion_batch_production_package_wave_items_planned_row_count_nonnegative check (
    planned_row_count >= 0
  )
);

create index if not exists ingestion_specs_project_id_idx
  on ingestion_platform.ingestion_specs (project_id);
create index if not exists ingestion_specs_project_kind_status_idx
  on ingestion_platform.ingestion_specs (project_id, spec_kind, status);

create index if not exists ingestion_admin_principals_email_idx
  on ingestion_platform.ingestion_admin_principals (lower(email));
create index if not exists ingestion_admin_principals_status_idx
  on ingestion_platform.ingestion_admin_principals (status, expires_at);

create index if not exists ingestion_sources_project_id_idx
  on ingestion_platform.ingestion_sources (project_id);
create index if not exists ingestion_sources_project_adapter_idx
  on ingestion_platform.ingestion_sources (project_id, adapter);

create index if not exists ingestion_targets_project_id_idx
  on ingestion_platform.ingestion_targets (project_id);
create index if not exists ingestion_targets_project_adapter_idx
  on ingestion_platform.ingestion_targets (project_id, adapter);

create index if not exists ingestion_runs_project_id_idx
  on ingestion_platform.ingestion_runs (project_id);
create index if not exists ingestion_runs_spec_id_idx
  on ingestion_platform.ingestion_runs (spec_id);
create index if not exists ingestion_runs_project_status_created_idx
  on ingestion_platform.ingestion_runs (project_id, status, created_at desc);

create index if not exists ingestion_tasks_project_id_idx
  on ingestion_platform.ingestion_tasks (project_id);
create index if not exists ingestion_tasks_run_id_idx
  on ingestion_platform.ingestion_tasks (run_id);
create index if not exists ingestion_tasks_source_id_idx
  on ingestion_platform.ingestion_tasks (source_id);
create index if not exists ingestion_tasks_target_id_idx
  on ingestion_platform.ingestion_tasks (target_id);
create index if not exists ingestion_tasks_status_next_attempt_idx
  on ingestion_platform.ingestion_tasks (status, next_attempt_at, priority desc);

create index if not exists ingestion_worker_leases_task_id_idx
  on ingestion_platform.ingestion_worker_leases (task_id);
create index if not exists ingestion_worker_leases_worker_status_idx
  on ingestion_platform.ingestion_worker_leases (worker_id, status);
create unique index if not exists ingestion_worker_leases_active_task_unique
  on ingestion_platform.ingestion_worker_leases (task_id)
  where status = 'active' and released_at is null;

create index if not exists ingestion_checkpoints_project_id_idx
  on ingestion_platform.ingestion_checkpoints (project_id);
create index if not exists ingestion_checkpoints_pipeline_spec_id_idx
  on ingestion_platform.ingestion_checkpoints (pipeline_spec_id);
create index if not exists ingestion_checkpoints_source_id_idx
  on ingestion_platform.ingestion_checkpoints (source_id);
create index if not exists ingestion_checkpoints_target_id_idx
  on ingestion_platform.ingestion_checkpoints (target_id);
create index if not exists ingestion_checkpoints_updated_by_run_id_idx
  on ingestion_platform.ingestion_checkpoints (updated_by_run_id);

create index if not exists ingestion_events_project_created_idx
  on ingestion_platform.ingestion_events (project_id, created_at desc);
create index if not exists ingestion_events_run_id_idx
  on ingestion_platform.ingestion_events (run_id);
create index if not exists ingestion_events_task_id_idx
  on ingestion_platform.ingestion_events (task_id);
create index if not exists ingestion_events_type_severity_idx
  on ingestion_platform.ingestion_events (event_type, severity);

create index if not exists ingestion_dead_letters_project_created_idx
  on ingestion_platform.ingestion_dead_letters (project_id, created_at desc);
create index if not exists ingestion_dead_letters_run_id_idx
  on ingestion_platform.ingestion_dead_letters (run_id);
create index if not exists ingestion_dead_letters_task_id_idx
  on ingestion_platform.ingestion_dead_letters (task_id);
create index if not exists ingestion_dead_letters_source_id_idx
  on ingestion_platform.ingestion_dead_letters (source_id);
create index if not exists ingestion_dead_letters_unresolved_idx
  on ingestion_platform.ingestion_dead_letters (project_id, reason_code, created_at desc)
  where resolved_at is null;

create index if not exists ingestion_artifacts_project_created_idx
  on ingestion_platform.ingestion_artifacts (project_id, created_at desc);
create index if not exists ingestion_artifacts_run_id_idx
  on ingestion_platform.ingestion_artifacts (run_id);
create index if not exists ingestion_artifacts_task_id_idx
  on ingestion_platform.ingestion_artifacts (task_id);

create index if not exists ingestion_policy_evaluations_project_decision_idx
  on ingestion_platform.ingestion_policy_evaluations (project_id, decision, created_at desc);
create index if not exists ingestion_policy_evaluations_run_id_idx
  on ingestion_platform.ingestion_policy_evaluations (run_id);
create index if not exists ingestion_policy_evaluations_task_id_idx
  on ingestion_platform.ingestion_policy_evaluations (task_id);
create index if not exists ingestion_policy_evaluations_source_id_idx
  on ingestion_platform.ingestion_policy_evaluations (source_id);

create index if not exists ingestion_promotions_project_status_idx
  on ingestion_platform.ingestion_promotions (project_id, status, created_at desc);
create index if not exists ingestion_promotions_source_evaluation_id_idx
  on ingestion_platform.ingestion_promotions (source_evaluation_id);

create index if not exists ingestion_shipments_project_status_idx
  on ingestion_platform.ingestion_shipments (project_id, status, created_at desc);
create index if not exists ingestion_shipments_run_id_idx
  on ingestion_platform.ingestion_shipments (run_id);
create index if not exists ingestion_shipments_target_id_idx
  on ingestion_platform.ingestion_shipments (target_id);

create index if not exists ingestion_shipment_items_shipment_id_idx
  on ingestion_platform.ingestion_shipment_items (shipment_id);
create index if not exists ingestion_shipment_items_status_idx
  on ingestion_platform.ingestion_shipment_items (shipment_id, status);

create index if not exists ingestion_audit_log_project_created_idx
  on ingestion_platform.ingestion_audit_log (project_id, created_at desc);
create index if not exists ingestion_audit_log_action_target_idx
  on ingestion_platform.ingestion_audit_log (action, target_type, created_at desc);

create index if not exists ingestion_schedule_proposals_project_status_idx
  on ingestion_platform.ingestion_schedule_proposals (project_id, work_status, created_at desc);

create index if not exists ingestion_batch_plans_project_status_idx
  on ingestion_platform.ingestion_batch_plans (project_id, status, updated_at desc);
create index if not exists ingestion_batch_plans_project_target_status_idx
  on ingestion_platform.ingestion_batch_plans (project_id, target_key, status, updated_at desc);

create index if not exists ingestion_batch_queue_items_plan_status_idx
  on ingestion_platform.ingestion_batch_queue_items (batch_plan_id, status);
create index if not exists ingestion_batch_queue_items_country_category_idx
  on ingestion_platform.ingestion_batch_queue_items (batch_plan_id, country_code, category);

create index if not exists ingestion_batch_dry_run_executions_plan_status_idx
  on ingestion_platform.ingestion_batch_dry_run_executions (batch_plan_id, status, updated_at desc);

create index if not exists ingestion_batch_canary_waves_plan_status_idx
  on ingestion_platform.ingestion_batch_canary_waves (batch_plan_id, status, updated_at desc);

create index if not exists ingestion_batch_production_package_waves_plan_status_idx
  on ingestion_platform.ingestion_batch_production_package_waves (batch_plan_id, status, updated_at desc);

create index if not exists ingestion_batch_production_package_waves_project_target_idx
  on ingestion_platform.ingestion_batch_production_package_waves (project_id, target_key, target_environment, status);

create index if not exists ingestion_batch_production_package_wave_items_wave_status_idx
  on ingestion_platform.ingestion_batch_production_package_wave_items (wave_id, status, run_order asc);

create index if not exists ingestion_batch_canary_wave_items_wave_status_idx
  on ingestion_platform.ingestion_batch_canary_wave_items (wave_id, status, run_order asc);

-- IP-18.7: human-approved autonomy envelope per source/target pair. Authority is
-- explicit target_environment plus stored bounds — never inferred from target key.
create table if not exists ingestion_platform.ingestion_autonomy_policies (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  policy_key text not null,
  source_key text not null,
  target_key text not null,
  target_environment text not null,
  ramp_mode text not null default 'bootstrap',
  status text not null default 'paused',
  allowed_tiers jsonb not null default '[]'::jsonb,
  allowed_geographies jsonb not null default '[]'::jsonb,
  allowed_categories jsonb not null default '[]'::jsonb,
  allowed_transitions jsonb not null default '[]'::jsonb,
  max_units_per_cycle integer not null,
  max_rows_per_cycle integer not null,
  rolling_limits jsonb not null default '{}'::jsonb,
  guard_thresholds jsonb not null default '{}'::jsonb,
  production_inbox_handoff_policy jsonb not null default '{}'::jsonb,
  policy_version integer not null default 1,
  approved_by text,
  approved_audit_id text,
  approval_reason text,
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_autonomy_policies_policy_key_unique unique (project_id, policy_key),
  constraint ingestion_autonomy_policies_target_environment_check check (
    target_environment in ('staging', 'production')
  ),
  constraint ingestion_autonomy_policies_status_check check (
    status in ('active', 'paused', 'disabled', 'archived')
  ),
  constraint ingestion_autonomy_policies_ramp_mode_check check (
    ramp_mode in ('bootstrap', 'staging_ramp', 'volume_ramp', 'steady_state')
  ),
  constraint ingestion_autonomy_policies_max_units_positive check (max_units_per_cycle > 0),
  constraint ingestion_autonomy_policies_max_rows_positive check (max_rows_per_cycle > 0),
  constraint ingestion_autonomy_policies_allowed_tiers_array check (
    jsonb_typeof(allowed_tiers) = 'array'
  ),
  constraint ingestion_autonomy_policies_allowed_geographies_array check (
    jsonb_typeof(allowed_geographies) = 'array'
  ),
  constraint ingestion_autonomy_policies_allowed_categories_array check (
    jsonb_typeof(allowed_categories) = 'array'
  ),
  constraint ingestion_autonomy_policies_allowed_transitions_array check (
    jsonb_typeof(allowed_transitions) = 'array'
  ),
  constraint ingestion_autonomy_policies_rolling_limits_object check (
    jsonb_typeof(rolling_limits) = 'object'
  ),
  constraint ingestion_autonomy_policies_guard_thresholds_object check (
    jsonb_typeof(guard_thresholds) = 'object'
  ),
  constraint ingestion_autonomy_policies_production_inbox_handoff_object check (
    jsonb_typeof(production_inbox_handoff_policy) = 'object'
  ),
  constraint ingestion_autonomy_policies_summary_object check (
    jsonb_typeof(summary) = 'object'
  )
);

alter table ingestion_platform.ingestion_autonomy_policies
  add column if not exists ramp_mode text not null default 'bootstrap';

alter table ingestion_platform.ingestion_autonomy_policies
  drop constraint if exists ingestion_autonomy_policies_ramp_mode_check;

alter table ingestion_platform.ingestion_autonomy_policies
  add constraint ingestion_autonomy_policies_ramp_mode_check check (
    ramp_mode in ('bootstrap', 'staging_ramp', 'volume_ramp', 'steady_state')
  );

update ingestion_platform.ingestion_autonomy_policies
set ramp_mode = coalesce(summary->>'rampMode', summary->'ramp'->>'mode')
where ramp_mode = 'bootstrap'
  and coalesce(summary->>'rampMode', summary->'ramp'->>'mode') in (
    'bootstrap',
    'staging_ramp',
    'volume_ramp',
    'steady_state'
  );

-- IP-18.7: append-mostly autonomy cycle ledger joining policy, queue units,
-- dry-run executions, staging waves, and future production packages.
create table if not exists ingestion_platform.ingestion_autonomy_runs (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  policy_id bigint not null references ingestion_platform.ingestion_autonomy_policies(id) on delete cascade,
  run_key text not null,
  phase text not null,
  status text not null default 'started',
  actor_type text not null,
  actor_id text not null,
  selected_units jsonb not null default '[]'::jsonb,
  scanned_count integer not null default 0,
  advanced_count integer not null default 0,
  blocked_count integer not null default 0,
  skipped_count integer not null default 0,
  highest_safety_mode text,
  guard_outcome jsonb not null default '{}'::jsonb,
  pause_reason text,
  recommended_action jsonb,
  telemetry_links jsonb not null default '{}'::jsonb,
  corrective_actions jsonb not null default '[]'::jsonb,
  dry_run_execution_key text,
  wave_key text,
  package_key text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_autonomy_runs_run_key_unique unique (policy_id, run_key),
  constraint ingestion_autonomy_runs_phase_check check (
    phase in ('planning', 'dry_run', 'staging_canary', 'production_inbox', 'corrective_action')
  ),
  constraint ingestion_autonomy_runs_status_check check (
    status in ('started', 'advanced', 'paused', 'completed', 'failed', 'skipped')
  ),
  constraint ingestion_autonomy_runs_actor_type_check check (
    actor_type in ('operator', 'system', 'worker', 'api', 'autonomous_agent')
  ),
  constraint ingestion_autonomy_runs_selected_units_array check (
    jsonb_typeof(selected_units) = 'array'
  ),
  constraint ingestion_autonomy_runs_guard_outcome_object check (
    jsonb_typeof(guard_outcome) = 'object'
  ),
  constraint ingestion_autonomy_runs_recommended_action_object check (
    recommended_action is null or jsonb_typeof(recommended_action) = 'object'
  ),
  constraint ingestion_autonomy_runs_telemetry_links_object check (
    jsonb_typeof(telemetry_links) = 'object'
  ),
  constraint ingestion_autonomy_runs_corrective_actions_array check (
    jsonb_typeof(corrective_actions) = 'array'
  ),
  constraint ingestion_autonomy_runs_scanned_count_nonnegative check (scanned_count >= 0),
  constraint ingestion_autonomy_runs_advanced_count_nonnegative check (advanced_count >= 0),
  constraint ingestion_autonomy_runs_blocked_count_nonnegative check (blocked_count >= 0),
  constraint ingestion_autonomy_runs_skipped_count_nonnegative check (skipped_count >= 0)
);

create index if not exists ingestion_autonomy_policies_project_status_idx
  on ingestion_platform.ingestion_autonomy_policies (project_id, status, updated_at desc);

create index if not exists ingestion_autonomy_runs_policy_status_idx
  on ingestion_platform.ingestion_autonomy_runs (policy_id, status, created_at desc);

create index if not exists ingestion_autonomy_runs_run_key_idx
  on ingestion_platform.ingestion_autonomy_runs (policy_id, run_key);

create index if not exists ingestion_autonomy_runs_created_at_idx
  on ingestion_platform.ingestion_autonomy_runs (created_at desc);

create or replace function ingestion_platform.promote_autonomy_ramp(
  p_project_key text,
  p_policy_key text,
  p_expected_current_mode text,
  p_requested_mode text,
  p_actor_type text,
  p_actor_id text,
  p_audit_reason text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
declare
  v_allowed_modes constant text[] := array['bootstrap', 'staging_ramp', 'volume_ramp', 'steady_state'];
  v_project_id bigint;
  v_policy_id bigint;
  v_policy_version integer;
  v_current_mode text;
  v_expected_rank integer;
  v_requested_rank integer;
  v_direction integer;
  v_audit_id bigint;
  v_event_type text;
  v_action text;
begin
  p_project_key := nullif(btrim(p_project_key), '');
  p_policy_key := nullif(btrim(p_policy_key), '');
  p_expected_current_mode := nullif(btrim(p_expected_current_mode), '');
  p_requested_mode := nullif(btrim(p_requested_mode), '');
  p_actor_type := nullif(btrim(p_actor_type), '');
  p_actor_id := nullif(btrim(p_actor_id), '');
  p_audit_reason := nullif(btrim(p_audit_reason), '');

  if p_project_key is null or p_policy_key is null then
    raise exception 'missing_policy_identity';
  end if;

  if p_actor_type is null or p_actor_id is null then
    raise exception 'missing_actor_identity';
  end if;

  if p_audit_reason is null then
    raise exception 'missing_audit_reason';
  end if;

  v_expected_rank := array_position(v_allowed_modes, p_expected_current_mode);
  v_requested_rank := array_position(v_allowed_modes, p_requested_mode);

  if v_expected_rank is null or v_requested_rank is null then
    raise exception 'unknown_mode';
  end if;

  if p_expected_current_mode = p_requested_mode then
    raise exception 'same_mode';
  end if;

  v_direction := v_requested_rank - v_expected_rank;

  if v_direction > 0 and p_requested_mode = 'steady_state' then
    raise exception 'steady_state_locked';
  end if;

  if v_direction > 1 then
    raise exception 'skips_required_ramp';
  end if;

  select
    p.id,
    ap.id,
    ap.policy_version,
    ap.ramp_mode
  into
    v_project_id,
    v_policy_id,
    v_policy_version,
    v_current_mode
  from ingestion_platform.ingestion_autonomy_policies ap
  join ingestion_platform.ingestion_projects p on p.id = ap.project_id
  where p.project_key = p_project_key
    and ap.policy_key = p_policy_key
  for update of ap;

  if v_policy_id is null then
    raise exception 'policy_not_found';
  end if;

  if v_current_mode <> p_expected_current_mode then
    raise exception 'ramp_mode_conflict';
  end if;

  update ingestion_platform.ingestion_autonomy_policies
  set ramp_mode = p_requested_mode,
      updated_at = now()
  where id = v_policy_id;

  v_action := case when v_direction > 0 then 'promote_autonomy_ramp' else 'demote_autonomy_ramp' end;
  v_event_type := case when v_direction > 0 then 'autonomy.ramp.promoted' else 'autonomy.ramp.demoted' end;

  insert into ingestion_platform.ingestion_audit_log (
    project_id,
    actor_type,
    actor_id,
    action,
    target_type,
    target_id,
    reason,
    payload
  )
  values (
    v_project_id,
    p_actor_type,
    p_actor_id,
    v_action,
    'autonomy_policy',
    v_policy_id::text,
    p_audit_reason,
    jsonb_build_object(
      'policyKey', p_policy_key,
      'policyVersion', v_policy_version,
      'fromMode', p_expected_current_mode,
      'toMode', p_requested_mode
    )
  )
  returning id into v_audit_id;

  insert into ingestion_platform.ingestion_events (
    project_id,
    event_type,
    severity,
    signal,
    message,
    payload
  )
  values (
    v_project_id,
    v_event_type,
    'info',
    'autonomy_ramp',
    format('Autonomy ramp changed from %s to %s for %s', p_expected_current_mode, p_requested_mode, p_policy_key),
    jsonb_build_object(
      'policyKey', p_policy_key,
      'policyVersion', v_policy_version,
      'fromMode', p_expected_current_mode,
      'toMode', p_requested_mode,
      'auditId', v_audit_id::text
    )
  );

  return jsonb_build_object(
    'ok', true,
    'policyId', v_policy_id::text,
    'fromMode', p_expected_current_mode,
    'toMode', p_requested_mode,
    'auditId', v_audit_id::text
  );
end;
$$;

revoke all on function ingestion_platform.promote_autonomy_ramp(
  text,
  text,
  text,
  text,
  text,
  text,
  text
) from public;

create or replace function ingestion_platform.set_autonomy_production_handoff(
  p_project_key text,
  p_policy_key text,
  p_expected_enabled boolean,
  p_requested_enabled boolean,
  p_actor_type text,
  p_actor_id text,
  p_audit_reason text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
declare
  v_project_id bigint;
  v_policy_id bigint;
  v_policy_version integer;
  v_current_enabled boolean;
  v_previous_policy jsonb;
  v_next_policy jsonb;
  v_previous_transitions jsonb;
  v_next_transitions jsonb;
  v_audit_id bigint;
  v_action text;
  v_event_type text;
begin
  p_project_key := nullif(btrim(p_project_key), '');
  p_policy_key := nullif(btrim(p_policy_key), '');
  p_actor_type := nullif(btrim(p_actor_type), '');
  p_actor_id := nullif(btrim(p_actor_id), '');
  p_audit_reason := nullif(btrim(p_audit_reason), '');

  if p_project_key is null or p_policy_key is null then
    raise exception 'missing_policy_identity';
  end if;

  if p_actor_type is null or p_actor_id is null then
    raise exception 'missing_actor_identity';
  end if;

  if p_expected_enabled is null or p_requested_enabled is null then
    raise exception 'missing_handoff_state';
  end if;

  if p_audit_reason is null then
    raise exception 'missing_audit_reason';
  end if;

  select
    p.id,
    ap.id,
    ap.policy_version,
    ap.production_inbox_handoff_policy,
    ap.allowed_transitions,
    case
      when ap.production_inbox_handoff_policy->>'requiresIp18_6' = 'true' then false
      when ap.production_inbox_handoff_policy->>'enabled' = 'true' then true
      else false
    end
  into
    v_project_id,
    v_policy_id,
    v_policy_version,
    v_previous_policy,
    v_previous_transitions,
    v_current_enabled
  from ingestion_platform.ingestion_autonomy_policies ap
  join ingestion_platform.ingestion_projects p on p.id = ap.project_id
  where p.project_key = p_project_key
    and ap.policy_key = p_policy_key
  for update of ap;

  if v_policy_id is null then
    raise exception 'policy_not_found';
  end if;

  if v_current_enabled <> p_expected_enabled then
    raise exception 'production_handoff_conflict';
  end if;

  if v_current_enabled = p_requested_enabled then
    raise exception 'same_production_handoff_state';
  end if;

  if p_requested_enabled then
    v_next_policy := jsonb_set(
      jsonb_set(
        jsonb_set(
          coalesce(v_previous_policy, '{}'::jsonb),
          '{enabled}',
          'true'::jsonb,
          true
        ),
        '{requiresIp18_6}',
        'false'::jsonb,
        true
      ),
      '{consumerApplyEnabled}',
      'false'::jsonb,
      true
    );

    select coalesce(jsonb_agg(value order by first_ord), '[]'::jsonb)
    into v_next_transitions
    from (
      select value, min(ord) as first_ord
      from (
        select value, ord::integer
        from jsonb_array_elements_text(v_previous_transitions) with ordinality as existing(value, ord)
        union all
        select 'approve_production_package_wave', 100000
        union all
        select 'deliver_production_package_wave', 100001
      ) combined
      group by value
    ) deduped;
  else
    v_next_policy := jsonb_set(
      jsonb_set(
        jsonb_set(
          coalesce(v_previous_policy, '{}'::jsonb),
          '{enabled}',
          'false'::jsonb,
          true
        ),
        '{requiresIp18_6}',
        'false'::jsonb,
        true
      ),
      '{consumerApplyEnabled}',
      'false'::jsonb,
      true
    );

    select coalesce(jsonb_agg(value order by ord), '[]'::jsonb)
    into v_next_transitions
    from jsonb_array_elements_text(v_previous_transitions) with ordinality as existing(value, ord)
    where value not in ('approve_production_package_wave', 'deliver_production_package_wave');
  end if;

  update ingestion_platform.ingestion_autonomy_policies
  set production_inbox_handoff_policy = v_next_policy,
      allowed_transitions = v_next_transitions,
      policy_version = policy_version + 1,
      approved_by = p_actor_id,
      approval_reason = p_audit_reason,
      updated_at = now()
  where id = v_policy_id;

  v_action := case
    when p_requested_enabled then 'enable_production_inbox_handoff'
    else 'disable_production_inbox_handoff'
  end;
  v_event_type := case
    when p_requested_enabled then 'autonomy.production_handoff.enabled'
    else 'autonomy.production_handoff.disabled'
  end;

  insert into ingestion_platform.ingestion_audit_log (
    project_id,
    actor_type,
    actor_id,
    action,
    target_type,
    target_id,
    reason,
    payload
  )
  values (
    v_project_id,
    p_actor_type,
    p_actor_id,
    v_action,
    'autonomy_policy',
    v_policy_id::text,
    p_audit_reason,
    jsonb_build_object(
      'policyKey', p_policy_key,
      'policyVersion', v_policy_version + 1,
      'fromEnabled', v_current_enabled,
      'toEnabled', p_requested_enabled,
      'beforeProductionInboxHandoffPolicy', v_previous_policy,
      'afterProductionInboxHandoffPolicy', v_next_policy,
      'beforeAllowedTransitions', v_previous_transitions,
      'afterAllowedTransitions', v_next_transitions
    )
  )
  returning id into v_audit_id;

  update ingestion_platform.ingestion_autonomy_policies
  set approved_audit_id = v_audit_id::text
  where id = v_policy_id;

  insert into ingestion_platform.ingestion_events (
    project_id,
    event_type,
    severity,
    signal,
    message,
    payload
  )
  values (
    v_project_id,
    v_event_type,
    'info',
    'autonomy_production_handoff',
    format('Production package autonomy handoff %s for %s',
      case when p_requested_enabled then 'enabled' else 'disabled' end,
      p_policy_key
    ),
    jsonb_build_object(
      'policyKey', p_policy_key,
      'policyVersion', v_policy_version + 1,
      'fromEnabled', v_current_enabled,
      'toEnabled', p_requested_enabled,
      'auditId', v_audit_id::text,
      'productionInboxHandoffPolicy', v_next_policy,
      'allowedTransitions', v_next_transitions
    )
  );

  return jsonb_build_object(
    'ok', true,
    'policyId', v_policy_id::text,
    'fromEnabled', v_current_enabled,
    'toEnabled', p_requested_enabled,
    'policyVersion', v_policy_version + 1,
    'auditId', v_audit_id::text,
    'productionInboxHandoffPolicy', v_next_policy,
    'allowedTransitions', v_next_transitions
  );
end;
$$;

revoke all on function ingestion_platform.set_autonomy_production_handoff(
  text,
  text,
  boolean,
  boolean,
  text,
  text,
  text
) from public;

-- IP-18.8.17 metadata-only batch-plan contract refresh. This fills a missing
-- source taxonomy without reseeding or updating queue rows/evidence.
create or replace function ingestion_platform.refresh_batch_plan_source_taxonomy(
  p_project_key text,
  p_plan_key text,
  p_source_key text,
  p_source_taxonomy jsonb,
  p_actor_type text,
  p_actor_id text,
  p_audit_reason text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
declare
  v_project_id bigint;
  v_plan_id bigint;
  v_plan_status text;
  v_plan_source_key text;
  v_existing_source_taxonomy jsonb;
  v_audit_id bigint;
begin
  p_project_key := nullif(btrim(p_project_key), '');
  p_plan_key := nullif(btrim(p_plan_key), '');
  p_source_key := nullif(btrim(p_source_key), '');
  p_actor_type := nullif(btrim(p_actor_type), '');
  p_actor_id := nullif(btrim(p_actor_id), '');
  p_audit_reason := nullif(btrim(p_audit_reason), '');

  if p_project_key is null or p_plan_key is null or p_source_key is null then
    raise exception 'missing_plan_identity';
  end if;
  if p_actor_type is null or p_actor_id is null then
    raise exception 'missing_actor_identity';
  end if;
  if p_audit_reason is null then
    raise exception 'missing_audit_reason';
  end if;
  if p_source_taxonomy is null or jsonb_typeof(p_source_taxonomy) <> 'object' then
    raise exception 'invalid_source_taxonomy';
  end if;

  select p.id, bp.id, bp.status, bp.source_key, bp.spec->'sourceTaxonomy'
  into v_project_id, v_plan_id, v_plan_status, v_plan_source_key, v_existing_source_taxonomy
  from ingestion_platform.ingestion_batch_plans bp
  join ingestion_platform.ingestion_projects p on p.id = bp.project_id
  where p.project_key = p_project_key and bp.plan_key = p_plan_key
  for update of bp;

  if v_plan_id is null then
    raise exception 'plan_not_found';
  end if;
  if v_plan_status <> 'active' then
    raise exception 'plan_not_active';
  end if;
  if v_plan_source_key <> p_source_key then
    raise exception 'plan_source_mismatch';
  end if;

  if v_existing_source_taxonomy is not null and jsonb_typeof(v_existing_source_taxonomy) <> 'null' then
    if v_existing_source_taxonomy <> p_source_taxonomy then
      raise exception 'source_taxonomy_already_present';
    end if;
    return jsonb_build_object(
      'ok', true,
      'changed', false,
      'planId', v_plan_id::text,
      'planKey', p_plan_key,
      'sourceKey', v_plan_source_key,
      'sourceTaxonomy', v_existing_source_taxonomy
    );
  end if;

  update ingestion_platform.ingestion_batch_plans
  set spec = jsonb_set(spec, '{sourceTaxonomy}', p_source_taxonomy, true),
      updated_at = now()
  where id = v_plan_id;

  insert into ingestion_platform.ingestion_audit_log (
    project_id, actor_type, actor_id, action, target_type, target_id, reason, payload
  ) values (
    v_project_id,
    p_actor_type,
    p_actor_id,
    'refresh_batch_plan_source_taxonomy',
    'batch_plan',
    v_plan_id::text,
    p_audit_reason,
    jsonb_build_object(
      'planKey', p_plan_key,
      'sourceKey', v_plan_source_key,
      'beforeSourceTaxonomy', v_existing_source_taxonomy,
      'afterSourceTaxonomy', p_source_taxonomy,
      'metadataOnly', true
    )
  ) returning id into v_audit_id;

  insert into ingestion_platform.ingestion_events (
    project_id, event_type, severity, signal, message, payload
  ) values (
    v_project_id,
    'batch_plan.source_taxonomy_refreshed',
    'info',
    'batch_plan_contract',
    format('Published source taxonomy added to batch plan %s', p_plan_key),
    jsonb_build_object(
      'planKey', p_plan_key,
      'sourceKey', v_plan_source_key,
      'auditId', v_audit_id::text,
      'metadataOnly', true
    )
  );

  return jsonb_build_object(
    'ok', true,
    'changed', true,
    'planId', v_plan_id::text,
    'planKey', p_plan_key,
    'sourceKey', v_plan_source_key,
    'auditId', v_audit_id::text,
    'sourceTaxonomy', p_source_taxonomy
  );
end;
$$;

revoke all on function ingestion_platform.refresh_batch_plan_source_taxonomy(
  text, text, text, jsonb, text, text, text
) from public;

create table if not exists ingestion_platform.ingestion_snapshot_releases (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  release_id text not null,
  source_key text not null,
  source_provider text not null,
  status text not null,
  acquired_at timestamptz not null,
  provenance_url text not null,
  input_sha256 text not null,
  output_sha256 text not null,
  source_attribution text not null,
  license_identifier text not null,
  retention_statement text not null,
  intended_consumer text not null,
  intended_target text not null,
  artifact_key text not null,
  artifact_uri text not null,
  coverage jsonb not null default '{}'::jsonb,
  row_counts jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_snapshot_releases_status_check check (
    status in ('acquired', 'validated', 'rejected', 'activation_ready', 'superseded')
  ),
  constraint ingestion_snapshot_releases_coverage_object check (
    jsonb_typeof(coverage) = 'object'
  ),
  constraint ingestion_snapshot_releases_row_counts_object check (
    jsonb_typeof(row_counts) = 'object'
  ),
  constraint ingestion_snapshot_releases_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  ),
  unique (project_id, release_id)
);

create index if not exists ingestion_snapshot_releases_project_status_idx
  on ingestion_platform.ingestion_snapshot_releases (project_id, status, created_at desc);

create index if not exists ingestion_snapshot_releases_source_output_idx
  on ingestion_platform.ingestion_snapshot_releases (source_key, output_sha256);

create or replace function ingestion_platform.register_snapshot_release(
  p_project_key text,
  p_release_id text,
  p_source_key text,
  p_source_provider text,
  p_acquired_at timestamptz,
  p_provenance_url text,
  p_input_sha256 text,
  p_output_sha256 text,
  p_source_attribution text,
  p_license_identifier text,
  p_retention_statement text,
  p_intended_consumer text,
  p_intended_target text,
  p_artifact_key text,
  p_artifact_uri text,
  p_coverage jsonb,
  p_actor_type text,
  p_actor_id text,
  p_audit_reason text,
  p_registration_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
declare
  v_project_id bigint;
  v_release_id bigint;
  v_audit_id bigint;
begin
  p_project_key := nullif(btrim(p_project_key), '');
  p_release_id := nullif(btrim(p_release_id), '');
  p_source_key := nullif(btrim(p_source_key), '');
  p_source_provider := nullif(btrim(p_source_provider), '');
  p_provenance_url := nullif(btrim(p_provenance_url), '');
  p_input_sha256 := nullif(btrim(p_input_sha256), '');
  p_output_sha256 := nullif(btrim(p_output_sha256), '');
  p_source_attribution := nullif(btrim(p_source_attribution), '');
  p_license_identifier := nullif(btrim(p_license_identifier), '');
  p_retention_statement := nullif(btrim(p_retention_statement), '');
  p_intended_consumer := nullif(btrim(p_intended_consumer), '');
  p_intended_target := nullif(btrim(p_intended_target), '');
  p_artifact_key := nullif(btrim(p_artifact_key), '');
  p_artifact_uri := nullif(btrim(p_artifact_uri), '');
  p_actor_type := nullif(btrim(p_actor_type), '');
  p_actor_id := nullif(btrim(p_actor_id), '');
  p_audit_reason := nullif(btrim(p_audit_reason), '');

  if p_project_key is null or p_release_id is null then
    raise exception 'missing_release_identity';
  end if;

  if p_actor_type is null or p_actor_id is null then
    raise exception 'missing_actor_identity';
  end if;

  if p_audit_reason is null then
    raise exception 'missing_audit_reason';
  end if;

  if p_coverage is null or jsonb_typeof(p_coverage) <> 'object' then
    raise exception 'invalid_coverage_payload';
  end if;

  select p.id
  into v_project_id
  from ingestion_platform.ingestion_projects p
  where p.project_key = p_project_key;

  if v_project_id is null then
    raise exception 'project_not_found';
  end if;

  insert into ingestion_platform.ingestion_snapshot_releases (
    project_id,
    release_id,
    source_key,
    source_provider,
    status,
    acquired_at,
    provenance_url,
    input_sha256,
    output_sha256,
    source_attribution,
    license_identifier,
    retention_statement,
    intended_consumer,
    intended_target,
    artifact_key,
    artifact_uri,
    coverage,
    row_counts,
    metadata,
    updated_at
  )
  values (
    v_project_id,
    p_release_id,
    p_source_key,
    p_source_provider,
    'activation_ready',
    p_acquired_at,
    p_provenance_url,
    p_input_sha256,
    p_output_sha256,
    p_source_attribution,
    p_license_identifier,
    p_retention_statement,
    p_intended_consumer,
    p_intended_target,
    p_artifact_key,
    p_artifact_uri,
    p_coverage,
    jsonb_build_object(
      'valid', coalesce((p_coverage->>'validRowCount')::integer, 0),
      'invalid', coalesce((p_coverage->>'invalidRowCount')::integer, 0),
      'duplicate', coalesce((p_coverage->>'duplicateRowCount')::integer, 0),
      'outOfScope', coalesce((p_coverage->>'outOfScopeRowCount')::integer, 0)
    ),
    jsonb_build_object('registeredBy', 'register_snapshot_release')
      || coalesce(p_registration_metadata, '{}'::jsonb),
    now()
  )
  on conflict (project_id, release_id) do update
  set
    status = excluded.status,
    output_sha256 = excluded.output_sha256,
    artifact_key = excluded.artifact_key,
    artifact_uri = excluded.artifact_uri,
    coverage = excluded.coverage,
    row_counts = excluded.row_counts,
    metadata = excluded.metadata,
    updated_at = now()
  returning id into v_release_id;

  insert into ingestion_platform.ingestion_audit_log (
    project_id,
    actor_type,
    actor_id,
    action,
    target_type,
    target_id,
    reason,
    payload
  )
  values (
    v_project_id,
    p_actor_type,
    p_actor_id,
    'register_snapshot_release',
    'snapshot_release',
    v_release_id::text,
    p_audit_reason,
    jsonb_build_object(
      'releaseId', p_release_id,
      'sourceKey', p_source_key,
      'sourceProvider', p_source_provider,
      'status', 'activation_ready',
      'artifactKey', p_artifact_key,
      'outputSha256', p_output_sha256
    )
  )
  returning id into v_audit_id;

  insert into ingestion_platform.ingestion_events (
    project_id,
    event_type,
    severity,
    signal,
    message,
    payload
  )
  values (
    v_project_id,
    'snapshot.release.registered',
    'info',
    'snapshot_release',
    format('Snapshot release %s registered as activation_ready', p_release_id),
    jsonb_build_object(
      'releaseId', p_release_id,
      'artifactKey', p_artifact_key,
      'auditId', v_audit_id::text
    )
  );

  return jsonb_build_object(
    'ok', true,
    'releaseId', p_release_id,
    'auditId', v_audit_id::text,
    'status', 'activation_ready'
  );
end;
$$;

revoke all on function ingestion_platform.register_snapshot_release(
  text,
  text,
  text,
  text,
  timestamptz,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb,
  text,
  text,
  text,
  jsonb
) from public;

create table if not exists ingestion_platform.ingestion_snapshot_release_plan_bindings (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  batch_plan_id bigint not null references ingestion_platform.ingestion_batch_plans(id) on delete cascade,
  release_id bigint not null references ingestion_platform.ingestion_snapshot_releases(id) on delete restrict,
  status text not null,
  artifact_bundle_sha256 text not null,
  coverage jsonb not null default '{}'::jsonb,
  activated_at timestamptz not null,
  activated_by_type text not null,
  activated_by_id text not null,
  audit_reason text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_snapshot_release_plan_bindings_status_check check (
    status in ('active', 'superseded')
  ),
  constraint ingestion_snapshot_release_plan_bindings_coverage_object check (
    jsonb_typeof(coverage) = 'object'
  )
);

create unique index if not exists ingestion_snapshot_release_plan_bindings_one_active_per_plan_idx
  on ingestion_platform.ingestion_snapshot_release_plan_bindings (batch_plan_id)
  where status = 'active';

create index if not exists ingestion_snapshot_release_plan_bindings_release_idx
  on ingestion_platform.ingestion_snapshot_release_plan_bindings (release_id, status);

create or replace function ingestion_platform.activate_snapshot_release(
  p_project_key text,
  p_plan_key text,
  p_release_id text,
  p_artifact_bundle_sha256 text,
  p_actor_type text,
  p_actor_id text,
  p_audit_reason text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
declare
  v_project_id bigint;
  v_plan_id bigint;
  v_plan_source_key text;
  v_plan_target_key text;
  v_release_row ingestion_platform.ingestion_snapshot_releases%rowtype;
  v_binding_id bigint;
  v_audit_id bigint;
begin
  p_project_key := nullif(btrim(p_project_key), '');
  p_plan_key := nullif(btrim(p_plan_key), '');
  p_release_id := nullif(btrim(p_release_id), '');
  p_artifact_bundle_sha256 := nullif(btrim(p_artifact_bundle_sha256), '');
  p_actor_type := nullif(btrim(p_actor_type), '');
  p_actor_id := nullif(btrim(p_actor_id), '');
  p_audit_reason := nullif(btrim(p_audit_reason), '');

  if p_project_key is null or p_plan_key is null or p_release_id is null then
    raise exception 'missing_activation_identity';
  end if;

  if p_artifact_bundle_sha256 is null then
    raise exception 'missing_artifact_bundle_sha256';
  end if;

  if p_artifact_bundle_sha256 !~ '^[a-f0-9]{64}$' then
    raise exception 'invalid_artifact_bundle_sha256';
  end if;

  if p_actor_type is null or p_actor_id is null then
    raise exception 'missing_actor_identity';
  end if;

  if p_audit_reason is null then
    raise exception 'missing_audit_reason';
  end if;

  select p.id
  into v_project_id
  from ingestion_platform.ingestion_projects p
  where p.project_key = p_project_key;

  if v_project_id is null then
    raise exception 'project_not_found';
  end if;

  select bp.id, bp.source_key, bp.target_key
  into v_plan_id, v_plan_source_key, v_plan_target_key
  from ingestion_platform.ingestion_batch_plans bp
  where bp.project_id = v_project_id
    and bp.plan_key = p_plan_key
  for update;

  if v_plan_id is null then
    raise exception 'batch_plan_not_found';
  end if;

  select *
  into v_release_row
  from ingestion_platform.ingestion_snapshot_releases r
  where r.project_id = v_project_id
    and r.release_id = p_release_id;

  if v_release_row.id is null then
    raise exception 'release_not_found';
  end if;

  if v_release_row.status <> 'activation_ready' then
    raise exception 'release_not_activation_ready';
  end if;

  if v_release_row.source_key <> v_plan_source_key then
    raise exception 'release_source_mismatch';
  end if;

  if v_release_row.intended_target <> v_plan_target_key then
    raise exception 'release_target_mismatch';
  end if;

  if v_release_row.intended_consumer <> p_project_key then
    raise exception 'release_consumer_mismatch';
  end if;

  update ingestion_platform.ingestion_snapshot_release_plan_bindings
  set status = 'superseded',
      updated_at = now()
  where batch_plan_id = v_plan_id
    and status = 'active';

  insert into ingestion_platform.ingestion_snapshot_release_plan_bindings (
    project_id,
    batch_plan_id,
    release_id,
    status,
    artifact_bundle_sha256,
    coverage,
    activated_at,
    activated_by_type,
    activated_by_id,
    audit_reason,
    created_at,
    updated_at
  )
  values (
    v_project_id,
    v_plan_id,
    v_release_row.id,
    'active',
    p_artifact_bundle_sha256,
    coalesce(v_release_row.coverage, '{}'::jsonb),
    now(),
    p_actor_type,
    p_actor_id,
    p_audit_reason,
    now(),
    now()
  )
  returning id into v_binding_id;

  insert into ingestion_platform.ingestion_audit_log (
    project_id,
    actor_type,
    actor_id,
    action,
    target_type,
    target_id,
    reason,
    payload,
    created_at
  )
  values (
    v_project_id,
    p_actor_type,
    p_actor_id,
    'activate_snapshot_release',
    'batch_plan',
    p_plan_key,
    p_audit_reason,
    jsonb_build_object(
      'releaseId', p_release_id,
      'artifactBundleSha256', p_artifact_bundle_sha256,
      'bindingId', v_binding_id
    ),
    now()
  )
  returning id into v_audit_id;

  insert into ingestion_platform.ingestion_events (
    project_id,
    event_type,
    severity,
    signal,
    message,
    payload
  )
  values (
    v_project_id,
    'snapshot.release.activated',
    'info',
    'snapshot.release.activated',
    format('Activated snapshot release %s for batch plan %s.', p_release_id, p_plan_key),
    jsonb_build_object(
      'releaseId', p_release_id,
      'planKey', p_plan_key,
      'bindingId', v_binding_id::text,
      'auditId', v_audit_id::text
    )
  );

  return jsonb_build_object(
    'ok', true,
    'bindingId', v_binding_id::text,
    'releaseId', p_release_id,
    'planKey', p_plan_key,
    'auditId', v_audit_id::text,
    'status', 'activated'
  );
end;
$$;

revoke all on function ingestion_platform.activate_snapshot_release(
  text,
  text,
  text,
  text,
  text,
  text,
  text
) from public;

-- IP-18.8.13 snapshot release commissioning requests
create table if not exists ingestion_platform.ingestion_snapshot_commission_requests (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  batch_plan_id bigint not null references ingestion_platform.ingestion_batch_plans(id) on delete cascade,
  source_key text not null,
  status text not null,
  countries jsonb not null,
  categories jsonb not null,
  max_rows_per_scope integer not null,
  audit_reason text not null,
  requested_by_type text not null,
  requested_by_id text not null,
  requested_at timestamptz not null default now(),
  claimed_at timestamptz,
  claimed_by_id text,
  worker_run_key text,
  claim_expires_at timestamptz,
  attempt_count integer not null default 0,
  registered_release_id text,
  error_code text,
  error_message text,
  failure_telemetry jsonb not null default '{}'::jsonb,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_snapshot_commission_requests_status_check check (
    status in ('requested', 'running', 'release_registered', 'activation_pending', 'failed')
  ),
  constraint ingestion_snapshot_commission_requests_countries_array check (
    jsonb_typeof(countries) = 'array'
  ),
  constraint ingestion_snapshot_commission_requests_categories_array check (
    jsonb_typeof(categories) = 'array'
  ),
  constraint ingestion_snapshot_commission_requests_max_rows_positive check (
    max_rows_per_scope > 0
  ),
  constraint ingestion_snapshot_commission_requests_attempt_count_nonnegative check (
    attempt_count >= 0
  ),
  constraint ingestion_snapshot_commission_requests_failure_telemetry_object check (
    jsonb_typeof(failure_telemetry) = 'object'
  )
);

alter table ingestion_platform.ingestion_snapshot_commission_requests
  add column if not exists failure_telemetry jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ingestion_snapshot_commission_requests_failure_telemetry_object'
      and conrelid = 'ingestion_platform.ingestion_snapshot_commission_requests'::regclass
  ) then
    alter table ingestion_platform.ingestion_snapshot_commission_requests
      add constraint ingestion_snapshot_commission_requests_failure_telemetry_object
      check (jsonb_typeof(failure_telemetry) = 'object');
  end if;
end;
$$;

create index if not exists ingestion_snapshot_commission_requests_project_plan_status_idx
  on ingestion_platform.ingestion_snapshot_commission_requests (project_id, batch_plan_id, status, requested_at desc);

create unique index if not exists ingestion_snapshot_commission_requests_one_active_per_plan_idx
  on ingestion_platform.ingestion_snapshot_commission_requests (project_id, batch_plan_id)
  where status in ('requested', 'running', 'release_registered');

create index if not exists ingestion_snapshot_commission_requests_worker_run_key_idx
  on ingestion_platform.ingestion_snapshot_commission_requests (worker_run_key)
  where worker_run_key is not null;

create index if not exists ingestion_snapshot_commission_requests_claim_expires_idx
  on ingestion_platform.ingestion_snapshot_commission_requests (status, claim_expires_at)
  where status in ('running', 'release_registered');

create or replace function ingestion_platform.create_snapshot_commission_request(
  p_project_key text,
  p_plan_key text,
  p_countries jsonb,
  p_categories jsonb,
  p_max_rows_per_scope integer,
  p_actor_type text,
  p_actor_id text,
  p_audit_reason text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
declare
  v_project_id bigint;
  v_plan_id bigint;
  v_plan_source_key text;
  v_plan_status text;
  v_request_id bigint;
  v_audit_id bigint;
begin
  p_project_key := nullif(btrim(p_project_key), '');
  p_plan_key := nullif(btrim(p_plan_key), '');
  p_actor_type := nullif(btrim(p_actor_type), '');
  p_actor_id := nullif(btrim(p_actor_id), '');
  p_audit_reason := nullif(btrim(p_audit_reason), '');

  if p_project_key is null or p_plan_key is null then
    raise exception 'missing_commission_identity';
  end if;

  if p_actor_type is null or p_actor_id is null then
    raise exception 'missing_actor_identity';
  end if;

  if p_audit_reason is null then
    raise exception 'missing_audit_reason';
  end if;

  if p_countries is null or jsonb_typeof(p_countries) <> 'array' or jsonb_array_length(p_countries) = 0 then
    raise exception 'invalid_countries';
  end if;

  if p_categories is null or jsonb_typeof(p_categories) <> 'array' or jsonb_array_length(p_categories) = 0 then
    raise exception 'invalid_categories';
  end if;

  if p_max_rows_per_scope is null or p_max_rows_per_scope <= 0 then
    raise exception 'invalid_max_rows_per_scope';
  end if;

  select p.id into v_project_id
  from ingestion_platform.ingestion_projects p
  where p.project_key = p_project_key;

  if v_project_id is null then
    raise exception 'project_not_found';
  end if;

  select bp.id, bp.source_key, bp.status
  into v_plan_id, v_plan_source_key, v_plan_status
  from ingestion_platform.ingestion_batch_plans bp
  where bp.project_id = v_project_id and bp.plan_key = p_plan_key;

  if v_plan_id is null then
    raise exception 'plan_not_found';
  end if;

  if v_plan_status is distinct from 'active' then
    raise exception 'plan_not_active';
  end if;

  if v_plan_source_key is distinct from 'fsq-os-places-snapshot' then
    raise exception 'unsupported_source_key';
  end if;

  begin
    insert into ingestion_platform.ingestion_snapshot_commission_requests (
      project_id,
      batch_plan_id,
      source_key,
      status,
      countries,
      categories,
      max_rows_per_scope,
      audit_reason,
      requested_by_type,
      requested_by_id,
      requested_at,
      updated_at
    )
    values (
      v_project_id,
      v_plan_id,
      v_plan_source_key,
      'requested',
      p_countries,
      p_categories,
      p_max_rows_per_scope,
      p_audit_reason,
      p_actor_type,
      p_actor_id,
      now(),
      now()
    )
    returning id into v_request_id;
  exception
    when unique_violation then
      raise exception 'commission_request_already_active';
  end;

  insert into ingestion_platform.ingestion_audit_log (
    project_id,
    actor_type,
    actor_id,
    action,
    target_type,
    target_id,
    reason,
    payload
  )
  values (
    v_project_id,
    p_actor_type,
    p_actor_id,
    'create_snapshot_commission_request',
    'snapshot_commission_request',
    v_request_id::text,
    p_audit_reason,
    jsonb_build_object(
      'requestId', v_request_id::text,
      'planKey', p_plan_key,
      'sourceKey', v_plan_source_key,
      'countries', p_countries,
      'categories', p_categories,
      'maxRowsPerScope', p_max_rows_per_scope,
      'status', 'requested'
    )
  )
  returning id into v_audit_id;

  insert into ingestion_platform.ingestion_events (
    project_id,
    event_type,
    severity,
    signal,
    message,
    payload
  )
  values (
    v_project_id,
    'snapshot.commission.requested',
    'info',
    'snapshot.commission.requested',
    format('Snapshot commission request %s created for plan %s.', v_request_id::text, p_plan_key),
    jsonb_build_object(
      'requestId', v_request_id::text,
      'planKey', p_plan_key,
      'auditId', v_audit_id::text
    )
  );

  return jsonb_build_object(
    'ok', true,
    'requestId', v_request_id::text,
    'auditId', v_audit_id::text,
    'status', 'requested',
    'sourceKey', v_plan_source_key
  );
end;
$$;

revoke all on function ingestion_platform.create_snapshot_commission_request(
  text,
  text,
  jsonb,
  jsonb,
  integer,
  text,
  text,
  text
) from public;

create or replace function ingestion_platform.claim_snapshot_commission_request(
  p_worker_id text,
  p_worker_run_key text,
  p_lease_seconds integer default 1800
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
declare
  v_request ingestion_platform.ingestion_snapshot_commission_requests%rowtype;
  v_project_key text;
  v_plan_key text;
begin
  p_worker_id := nullif(btrim(p_worker_id), '');
  p_worker_run_key := nullif(btrim(p_worker_run_key), '');

  if p_worker_id is null or p_worker_run_key is null then
    raise exception 'missing_worker_identity';
  end if;

  if p_lease_seconds is null or p_lease_seconds <= 0 then
    raise exception 'invalid_lease_seconds';
  end if;

  select r.*
  into v_request
  from ingestion_platform.ingestion_snapshot_commission_requests r
  where r.worker_run_key = p_worker_run_key
    and r.status in ('running', 'release_registered', 'activation_pending')
  limit 1;

  if found then
    select p.project_key, bp.plan_key
    into v_project_key, v_plan_key
    from ingestion_platform.ingestion_projects p
    join ingestion_platform.ingestion_batch_plans bp on bp.project_id = p.id and bp.id = v_request.batch_plan_id
    where p.id = v_request.project_id;

    return jsonb_build_object(
      'ok', true,
      'idempotentReplay', true,
      'requestId', v_request.id::text,
      'projectKey', v_project_key,
      'planKey', v_plan_key,
      'sourceKey', v_request.source_key,
      'status', v_request.status,
      'countries', v_request.countries,
      'categories', v_request.categories,
      'maxRowsPerScope', v_request.max_rows_per_scope,
      'registeredReleaseId', v_request.registered_release_id,
      'attemptCount', v_request.attempt_count,
      'claimExpiresAt', v_request.claim_expires_at
    );
  end if;

  select r.*
  into v_request
  from ingestion_platform.ingestion_snapshot_commission_requests r
  where r.status in ('running', 'release_registered')
    and r.claim_expires_at is not null
    and r.claim_expires_at < now()
  order by r.requested_at asc, r.id asc
  for update skip locked
  limit 1;

  if found then
    update ingestion_platform.ingestion_snapshot_commission_requests
    set
      status = case when v_request.status = 'release_registered' then 'release_registered' else 'running' end,
      claimed_at = now(),
      claimed_by_id = p_worker_id,
      worker_run_key = p_worker_run_key,
      claim_expires_at = now() + make_interval(secs => p_lease_seconds),
      attempt_count = v_request.attempt_count + 1,
      updated_at = now()
    where id = v_request.id
    returning * into v_request;

    select p.project_key, bp.plan_key
    into v_project_key, v_plan_key
    from ingestion_platform.ingestion_projects p
    join ingestion_platform.ingestion_batch_plans bp on bp.project_id = p.id and bp.id = v_request.batch_plan_id
    where p.id = v_request.project_id;

    return jsonb_build_object(
      'ok', true,
      'idempotentReplay', false,
      'leaseReclaimed', true,
      'requestId', v_request.id::text,
      'projectKey', v_project_key,
      'planKey', v_plan_key,
      'sourceKey', v_request.source_key,
      'status', v_request.status,
      'countries', v_request.countries,
      'categories', v_request.categories,
      'maxRowsPerScope', v_request.max_rows_per_scope,
      'registeredReleaseId', v_request.registered_release_id,
      'attemptCount', v_request.attempt_count,
      'claimExpiresAt', v_request.claim_expires_at
    );
  end if;

  select r.*
  into v_request
  from ingestion_platform.ingestion_snapshot_commission_requests r
  where r.status = 'requested'
  order by r.requested_at asc, r.id asc
  for update skip locked
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'no_pending_request');
  end if;

  update ingestion_platform.ingestion_snapshot_commission_requests
  set
    status = 'running',
    claimed_at = now(),
    claimed_by_id = p_worker_id,
    worker_run_key = p_worker_run_key,
    claim_expires_at = now() + make_interval(secs => p_lease_seconds),
    attempt_count = v_request.attempt_count + 1,
    updated_at = now()
  where id = v_request.id
  returning * into v_request;

  select p.project_key, bp.plan_key
  into v_project_key, v_plan_key
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp on bp.project_id = p.id and bp.id = v_request.batch_plan_id
  where p.id = v_request.project_id;

  return jsonb_build_object(
    'ok', true,
    'idempotentReplay', false,
    'leaseReclaimed', false,
    'requestId', v_request.id::text,
    'projectKey', v_project_key,
    'planKey', v_plan_key,
    'sourceKey', v_request.source_key,
    'status', v_request.status,
    'countries', v_request.countries,
    'categories', v_request.categories,
    'maxRowsPerScope', v_request.max_rows_per_scope,
    'registeredReleaseId', v_request.registered_release_id,
    'attemptCount', v_request.attempt_count,
    'claimExpiresAt', v_request.claim_expires_at
  );
end;
$$;

revoke all on function ingestion_platform.claim_snapshot_commission_request(
  text,
  text,
  integer
) from public;

create or replace function ingestion_platform.complete_snapshot_commission_request(
  p_request_id bigint,
  p_worker_run_key text,
  p_status text,
  p_registered_release_id text,
  p_error_code text,
  p_error_message text,
  p_failure_telemetry jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
declare
  v_request ingestion_platform.ingestion_snapshot_commission_requests%rowtype;
  v_audit_id bigint;
begin
  p_worker_run_key := nullif(btrim(p_worker_run_key), '');
  p_status := nullif(btrim(p_status), '');
  p_registered_release_id := nullif(btrim(p_registered_release_id), '');
  p_error_code := nullif(btrim(p_error_code), '');
  p_error_message := nullif(btrim(p_error_message), '');
  p_failure_telemetry := coalesce(p_failure_telemetry, '{}'::jsonb);

  if p_worker_run_key is null or p_status is null then
    raise exception 'missing_completion_identity';
  end if;

  if p_status not in ('release_registered', 'activation_pending', 'failed') then
    raise exception 'invalid_completion_status';
  end if;

  select *
  into v_request
  from ingestion_platform.ingestion_snapshot_commission_requests
  where id = p_request_id and worker_run_key = p_worker_run_key
  for update;

  if not found then
    raise exception 'commission_request_not_claimed';
  end if;

  if v_request.status in ('activation_pending', 'failed') then
    return jsonb_build_object(
      'ok', true,
      'idempotentReplay', true,
      'requestId', v_request.id::text,
      'status', v_request.status,
      'registeredReleaseId', v_request.registered_release_id
    );
  end if;

  if p_status = 'release_registered' and v_request.status <> 'running' then
    raise exception 'invalid_status_transition';
  end if;

  if p_status = 'activation_pending' and v_request.status not in ('running', 'release_registered') then
    raise exception 'invalid_status_transition';
  end if;

  if p_status = 'failed' and v_request.status not in ('running', 'release_registered') then
    raise exception 'invalid_status_transition';
  end if;

  if p_status in ('release_registered', 'activation_pending') and p_registered_release_id is null then
    raise exception 'missing_registered_release_id';
  end if;

  if p_status = 'failed' and p_error_code is null then
    raise exception 'missing_error_code';
  end if;

  if jsonb_typeof(p_failure_telemetry) <> 'object' then
    raise exception 'invalid_failure_telemetry';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(p_failure_telemetry) as telemetry_key(key)
    where key not in (
      'traceId',
      'stage',
      'classification',
      'errorFingerprint',
      'sourceErrorCode'
    )
  ) then
    raise exception 'invalid_failure_telemetry';
  end if;

  if p_status = 'failed' and (
    nullif(btrim(p_failure_telemetry->>'traceId'), '') is null or
    nullif(btrim(p_failure_telemetry->>'stage'), '') is null or
    nullif(btrim(p_failure_telemetry->>'classification'), '') is null
  ) then
    raise exception 'missing_failure_telemetry';
  end if;

  if p_status = 'failed' and (
    p_failure_telemetry->>'traceId' !~ '^[A-Za-z0-9-]{1,128}$' or
    p_failure_telemetry->>'stage' not in (
      'portal',
      'artifact_store',
      'release_registry',
      'contract',
      'intake',
      'control_plane',
      'worker'
    ) or
    p_failure_telemetry->>'classification' !~ '^[a-z0-9_-]{1,96}$' or
    (
      p_failure_telemetry ? 'errorFingerprint' and
      p_failure_telemetry->>'errorFingerprint' !~ '^[A-Fa-f0-9]{64}$'
    ) or
    (
      p_failure_telemetry ? 'sourceErrorCode' and
      p_failure_telemetry->>'sourceErrorCode' !~ '^[A-Za-z0-9_-]{1,32}$'
    )
  ) then
    raise exception 'invalid_failure_telemetry';
  end if;

  update ingestion_platform.ingestion_snapshot_commission_requests
  set
    status = p_status,
    registered_release_id = coalesce(p_registered_release_id, registered_release_id),
    error_code = p_error_code,
    error_message = p_error_message,
    failure_telemetry = case when p_status = 'failed' then p_failure_telemetry else failure_telemetry end,
    completed_at = case when p_status in ('activation_pending', 'failed') then now() else completed_at end,
    claim_expires_at = case
      when p_status in ('activation_pending', 'failed') then null
      else claim_expires_at
    end,
    updated_at = now()
  where id = v_request.id
  returning * into v_request;

  insert into ingestion_platform.ingestion_audit_log (
    project_id,
    actor_type,
    actor_id,
    action,
    target_type,
    target_id,
    reason,
    payload
  )
  values (
    v_request.project_id,
    'worker',
    v_request.claimed_by_id,
    'complete_snapshot_commission_request',
    'snapshot_commission_request',
    v_request.id::text,
    v_request.audit_reason,
    jsonb_build_object(
      'requestId', v_request.id::text,
      'status', v_request.status,
      'registeredReleaseId', v_request.registered_release_id,
      'errorCode', v_request.error_code,
      'failureTelemetry', case when v_request.status = 'failed' then v_request.failure_telemetry else null end
    )
  )
  returning id into v_audit_id;

  if v_request.status = 'failed' then
    insert into ingestion_platform.ingestion_events (
      project_id,
      event_type,
      severity,
      signal,
      message,
      payload
    )
    values (
      v_request.project_id,
      'snapshot_commission.failed',
      'error',
      v_request.error_code,
      coalesce(v_request.error_message, 'Snapshot commissioning failed.'),
      jsonb_build_object(
        'requestId', v_request.id::text,
        'workerRunKey', v_request.worker_run_key,
        'traceId', v_request.failure_telemetry->>'traceId',
        'stage', v_request.failure_telemetry->>'stage',
        'classification', v_request.failure_telemetry->>'classification',
        'errorFingerprint', v_request.failure_telemetry->>'errorFingerprint',
        'sourceErrorCode', v_request.failure_telemetry->>'sourceErrorCode'
      )
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'idempotentReplay', false,
    'requestId', v_request.id::text,
    'status', v_request.status,
    'registeredReleaseId', v_request.registered_release_id,
    'auditId', v_audit_id::text,
    'failureTelemetry', case when v_request.status = 'failed' then v_request.failure_telemetry else null end
  );
end;
$$;

revoke all on function ingestion_platform.complete_snapshot_commission_request(
  bigint,
  text,
  text,
  text,
  text,
  text,
  jsonb
) from public;

-- Compatibility wrapper for a worker process that started before the telemetry
-- signature upgrade. It still records an explicit legacy diagnostic rather than
-- silently dropping the failure trace.
create or replace function ingestion_platform.complete_snapshot_commission_request(
  p_request_id bigint,
  p_worker_run_key text,
  p_status text,
  p_registered_release_id text,
  p_error_code text,
  p_error_message text
) returns jsonb
language sql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
  select ingestion_platform.complete_snapshot_commission_request(
    p_request_id,
    p_worker_run_key,
    p_status,
    p_registered_release_id,
    p_error_code,
    p_error_message,
    case when p_status = 'failed' then jsonb_build_object(
      'traceId', 'legacy-' || p_request_id::text || '-' || floor(extract(epoch from statement_timestamp()))::text,
      'stage', 'worker',
      'classification', coalesce(nullif(btrim(p_error_code), ''), 'legacy_failure')
    ) else '{}'::jsonb end
  );
$$;

revoke all on function ingestion_platform.complete_snapshot_commission_request(
  bigint,
  text,
  text,
  text,
  text,
  text
) from public;

-- IP-18.8.14 separately confirmed snapshot activation requests
create table if not exists ingestion_platform.ingestion_snapshot_activation_requests (
  id bigint generated always as identity primary key,
  project_id bigint not null references ingestion_platform.ingestion_projects(id) on delete cascade,
  batch_plan_id bigint not null references ingestion_platform.ingestion_batch_plans(id) on delete cascade,
  commission_request_id bigint not null references ingestion_platform.ingestion_snapshot_commission_requests(id) on delete restrict,
  release_id text not null,
  status text not null,
  audit_reason text not null,
  requested_by_type text not null,
  requested_by_id text not null,
  requested_at timestamptz not null default now(),
  claimed_at timestamptz,
  claimed_by_id text,
  worker_run_key text,
  claim_expires_at timestamptz,
  attempt_count integer not null default 0,
  binding_id bigint,
  activation_audit_id bigint,
  error_code text,
  error_message text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_snapshot_activation_requests_status_check check (
    status in ('requested', 'running', 'activated', 'failed')
  ),
  constraint ingestion_snapshot_activation_requests_attempt_count_nonnegative check (
    attempt_count >= 0
  )
);

create index if not exists ingestion_snapshot_activation_requests_project_plan_status_idx
  on ingestion_platform.ingestion_snapshot_activation_requests (project_id, batch_plan_id, status, requested_at desc);

create unique index if not exists ingestion_snapshot_activation_requests_one_active_per_plan_idx
  on ingestion_platform.ingestion_snapshot_activation_requests (project_id, batch_plan_id)
  where status in ('requested', 'running');

create index if not exists ingestion_snapshot_activation_requests_worker_run_key_idx
  on ingestion_platform.ingestion_snapshot_activation_requests (worker_run_key)
  where worker_run_key is not null;

create index if not exists ingestion_snapshot_activation_requests_claim_expires_idx
  on ingestion_platform.ingestion_snapshot_activation_requests (status, claim_expires_at)
  where status = 'running';

create or replace function ingestion_platform.create_snapshot_activation_request(
  p_project_key text,
  p_plan_key text,
  p_commission_request_id bigint,
  p_release_id text,
  p_actor_type text,
  p_actor_id text,
  p_audit_reason text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
declare
  v_project_id bigint;
  v_plan_id bigint;
  v_plan_source_key text;
  v_plan_status text;
  v_commission_release_id text;
  v_commission_status text;
  v_release_source_key text;
  v_release_status text;
  v_request_id bigint;
  v_audit_id bigint;
begin
  p_project_key := nullif(btrim(p_project_key), '');
  p_plan_key := nullif(btrim(p_plan_key), '');
  p_release_id := nullif(btrim(p_release_id), '');
  p_actor_type := nullif(btrim(p_actor_type), '');
  p_actor_id := nullif(btrim(p_actor_id), '');
  p_audit_reason := nullif(btrim(p_audit_reason), '');

  if p_project_key is null or p_plan_key is null or p_commission_request_id is null or p_release_id is null then
    raise exception 'missing_activation_identity';
  end if;
  if p_actor_type is null or p_actor_id is null then
    raise exception 'missing_actor_identity';
  end if;
  if p_audit_reason is null then
    raise exception 'missing_audit_reason';
  end if;

  select p.id into v_project_id
  from ingestion_platform.ingestion_projects p
  where p.project_key = p_project_key;
  if v_project_id is null then
    raise exception 'project_not_found';
  end if;

  select bp.id, bp.source_key, bp.status
  into v_plan_id, v_plan_source_key, v_plan_status
  from ingestion_platform.ingestion_batch_plans bp
  where bp.project_id = v_project_id and bp.plan_key = p_plan_key;
  if v_plan_id is null then
    raise exception 'plan_not_found';
  end if;
  if v_plan_status is distinct from 'active' then
    raise exception 'plan_not_active';
  end if;

  select c.registered_release_id, c.status
  into v_commission_release_id, v_commission_status
  from ingestion_platform.ingestion_snapshot_commission_requests c
  where c.id = p_commission_request_id
    and c.project_id = v_project_id
    and c.batch_plan_id = v_plan_id;
  if v_commission_status is distinct from 'activation_pending'
    or v_commission_release_id is distinct from p_release_id then
    raise exception 'release_not_activation_pending';
  end if;

  select r.source_key, r.status
  into v_release_source_key, v_release_status
  from ingestion_platform.ingestion_snapshot_releases r
  where r.project_id = v_project_id and r.release_id = p_release_id;
  if v_release_status is distinct from 'activation_ready' then
    raise exception 'release_not_activation_ready';
  end if;
  if v_release_source_key is distinct from v_plan_source_key then
    raise exception 'release_source_mismatch';
  end if;

  begin
    insert into ingestion_platform.ingestion_snapshot_activation_requests (
      project_id, batch_plan_id, commission_request_id, release_id, status,
      audit_reason, requested_by_type, requested_by_id, requested_at, updated_at
    ) values (
      v_project_id, v_plan_id, p_commission_request_id, p_release_id, 'requested',
      p_audit_reason, p_actor_type, p_actor_id, now(), now()
    ) returning id into v_request_id;
  exception
    when unique_violation then
      raise exception 'activation_request_already_active';
  end;

  insert into ingestion_platform.ingestion_audit_log (
    project_id, actor_type, actor_id, action, target_type, target_id, reason, payload
  ) values (
    v_project_id, p_actor_type, p_actor_id,
    'create_snapshot_activation_request', 'snapshot_activation_request',
    v_request_id::text, p_audit_reason,
    jsonb_build_object(
      'requestId', v_request_id::text,
      'planKey', p_plan_key,
      'commissionRequestId', p_commission_request_id::text,
      'releaseId', p_release_id,
      'status', 'requested'
    )
  ) returning id into v_audit_id;

  insert into ingestion_platform.ingestion_events (
    project_id, event_type, severity, signal, message, payload
  ) values (
    v_project_id,
    'snapshot.activation.requested',
    'info',
    'snapshot.activation.requested',
    format('Snapshot activation request %s created for plan %s.', v_request_id::text, p_plan_key),
    jsonb_build_object('requestId', v_request_id::text, 'planKey', p_plan_key, 'auditId', v_audit_id::text)
  );

  return jsonb_build_object(
    'ok', true,
    'requestId', v_request_id::text,
    'auditId', v_audit_id::text,
    'status', 'requested',
    'releaseId', p_release_id
  );
end;
$$;

revoke all on function ingestion_platform.create_snapshot_activation_request(
  text, text, bigint, text, text, text, text
) from public;

create or replace function ingestion_platform.claim_snapshot_activation_request(
  p_worker_id text,
  p_worker_run_key text,
  p_lease_seconds integer default 1800
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
declare
  v_request ingestion_platform.ingestion_snapshot_activation_requests%rowtype;
  v_project_key text;
  v_plan_key text;
begin
  p_worker_id := nullif(btrim(p_worker_id), '');
  p_worker_run_key := nullif(btrim(p_worker_run_key), '');
  if p_worker_id is null or p_worker_run_key is null then
    raise exception 'missing_worker_identity';
  end if;
  if p_lease_seconds is null or p_lease_seconds <= 0 then
    raise exception 'invalid_lease_seconds';
  end if;

  select r.* into v_request
  from ingestion_platform.ingestion_snapshot_activation_requests r
  where r.worker_run_key = p_worker_run_key
  limit 1;

  if found then
    select p.project_key, bp.plan_key into v_project_key, v_plan_key
    from ingestion_platform.ingestion_projects p
    join ingestion_platform.ingestion_batch_plans bp on bp.project_id = p.id and bp.id = v_request.batch_plan_id
    where p.id = v_request.project_id;
    return jsonb_build_object(
      'ok', true, 'idempotentReplay', true,
      'requestId', v_request.id::text, 'projectKey', v_project_key, 'planKey', v_plan_key,
      'commissionRequestId', v_request.commission_request_id::text, 'releaseId', v_request.release_id,
      'status', v_request.status, 'attemptCount', v_request.attempt_count,
      'claimExpiresAt', v_request.claim_expires_at, 'bindingId', v_request.binding_id::text,
      'activationAuditId', v_request.activation_audit_id::text,
      'errorCode', v_request.error_code, 'errorMessage', v_request.error_message
    );
  end if;

  select r.* into v_request
  from ingestion_platform.ingestion_snapshot_activation_requests r
  where r.status = 'running' and r.claim_expires_at is not null and r.claim_expires_at < now()
  order by r.requested_at asc, r.id asc
  for update skip locked limit 1;

  if found then
    update ingestion_platform.ingestion_snapshot_activation_requests
    set claimed_at = now(), claimed_by_id = p_worker_id, worker_run_key = p_worker_run_key,
        claim_expires_at = now() + make_interval(secs => p_lease_seconds),
        attempt_count = v_request.attempt_count + 1, updated_at = now()
    where id = v_request.id returning * into v_request;
  else
    select r.* into v_request
    from ingestion_platform.ingestion_snapshot_activation_requests r
    where r.status = 'requested'
    order by r.requested_at asc, r.id asc
    for update skip locked limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'code', 'no_pending_request');
    end if;
    update ingestion_platform.ingestion_snapshot_activation_requests
    set status = 'running', claimed_at = now(), claimed_by_id = p_worker_id, worker_run_key = p_worker_run_key,
        claim_expires_at = now() + make_interval(secs => p_lease_seconds),
        attempt_count = v_request.attempt_count + 1, updated_at = now()
    where id = v_request.id returning * into v_request;
  end if;

  select p.project_key, bp.plan_key into v_project_key, v_plan_key
  from ingestion_platform.ingestion_projects p
  join ingestion_platform.ingestion_batch_plans bp on bp.project_id = p.id and bp.id = v_request.batch_plan_id
  where p.id = v_request.project_id;
  return jsonb_build_object(
    'ok', true, 'idempotentReplay', false,
    'requestId', v_request.id::text, 'projectKey', v_project_key, 'planKey', v_plan_key,
    'commissionRequestId', v_request.commission_request_id::text, 'releaseId', v_request.release_id,
    'status', v_request.status, 'attemptCount', v_request.attempt_count,
    'claimExpiresAt', v_request.claim_expires_at
  );
end;
$$;

revoke all on function ingestion_platform.claim_snapshot_activation_request(text, text, integer) from public;

create or replace function ingestion_platform.complete_snapshot_activation_request(
  p_request_id bigint,
  p_worker_run_key text,
  p_status text,
  p_binding_id bigint,
  p_activation_audit_id bigint,
  p_error_code text,
  p_error_message text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
as $$
declare
  v_request ingestion_platform.ingestion_snapshot_activation_requests%rowtype;
  v_audit_id bigint;
begin
  p_worker_run_key := nullif(btrim(p_worker_run_key), '');
  p_status := nullif(btrim(p_status), '');
  p_error_code := nullif(btrim(p_error_code), '');
  p_error_message := nullif(btrim(p_error_message), '');
  if p_worker_run_key is null or p_status is null then
    raise exception 'missing_completion_identity';
  end if;
  if p_status not in ('activated', 'failed') then
    raise exception 'invalid_completion_status';
  end if;
  select * into v_request
  from ingestion_platform.ingestion_snapshot_activation_requests
  where id = p_request_id and worker_run_key = p_worker_run_key
  for update;
  if not found then
    raise exception 'activation_request_not_claimed';
  end if;
  if v_request.status in ('activated', 'failed') then
    return jsonb_build_object('ok', true, 'idempotentReplay', true, 'requestId', v_request.id::text, 'status', v_request.status);
  end if;
  if v_request.status <> 'running' then
    raise exception 'invalid_status_transition';
  end if;
  if p_status = 'activated' and (p_binding_id is null or p_activation_audit_id is null) then
    raise exception 'missing_activation_result';
  end if;
  if p_status = 'failed' and p_error_code is null then
    raise exception 'missing_error_code';
  end if;

  update ingestion_platform.ingestion_snapshot_activation_requests
  set status = p_status,
      binding_id = case when p_status = 'activated' then p_binding_id else binding_id end,
      activation_audit_id = case when p_status = 'activated' then p_activation_audit_id else activation_audit_id end,
      error_code = p_error_code,
      error_message = p_error_message,
      completed_at = now(), claim_expires_at = null, updated_at = now()
  where id = v_request.id returning * into v_request;

  insert into ingestion_platform.ingestion_audit_log (
    project_id, actor_type, actor_id, action, target_type, target_id, reason, payload
  ) values (
    v_request.project_id, 'worker', v_request.claimed_by_id,
    'complete_snapshot_activation_request', 'snapshot_activation_request',
    v_request.id::text, v_request.audit_reason,
    jsonb_build_object(
      'requestId', v_request.id::text, 'status', v_request.status,
      'releaseId', v_request.release_id, 'bindingId', v_request.binding_id,
      'activationAuditId', v_request.activation_audit_id, 'errorCode', v_request.error_code
    )
  ) returning id into v_audit_id;

  return jsonb_build_object(
    'ok', true, 'idempotentReplay', false,
    'requestId', v_request.id::text, 'status', v_request.status, 'auditId', v_audit_id::text
  );
end;
$$;

revoke all on function ingestion_platform.complete_snapshot_activation_request(
  bigint, text, text, bigint, bigint, text, text
) from public;

commit;
