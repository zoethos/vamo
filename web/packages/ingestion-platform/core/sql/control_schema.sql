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

commit;
