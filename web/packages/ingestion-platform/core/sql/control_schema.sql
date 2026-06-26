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
    actor_type in ('operator', 'system', 'worker', 'api')
  ),
  constraint ingestion_audit_log_payload_object check (
    jsonb_typeof(payload) = 'object'
  )
);

create index if not exists ingestion_specs_project_id_idx
  on ingestion_platform.ingestion_specs (project_id);
create index if not exists ingestion_specs_project_kind_status_idx
  on ingestion_platform.ingestion_specs (project_id, spec_kind, status);

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

commit;
