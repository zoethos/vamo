-- Bootstrap companion for the Confluendo control-plane database.
--
-- Before running, positively confirm the Supabase project/database is the
-- Confluendo control DB. Postgres roles are cluster-level, so the presence of
-- confluendo_app is not by itself a safe target-database proof.
--
-- Run order:
-- 1. Run core/sql/control_schema.sql as the database owner.
-- 2. Run this file as the database owner.
-- 3. Seed the first admin principal with the optional block at the bottom.
--
-- This file intentionally grants the dashboard runtime role only the
-- permissions it needs today. Worker ingestion grants should use a separate
-- worker role when the worker is connected to the managed control DB.

begin;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'confluendo_app') then
    raise exception 'Postgres role confluendo_app does not exist. Create it before running this bootstrap.';
  end if;
end $$;

insert into ingestion_platform.ingestion_projects (
  project_key,
  display_name,
  description,
  metadata
)
values (
  'vamo',
  'Vamo',
  'First consumer project for the Confluendo ingestion control plane.',
  '{"consumer":"vamo","controlPlane":"confluendo-control"}'::jsonb
)
on conflict (project_key) do update
set
  display_name = excluded.display_name,
  description = excluded.description,
  metadata = ingestion_platform.ingestion_projects.metadata || excluded.metadata,
  updated_at = now();

grant usage on schema ingestion_platform to confluendo_app;

grant select on all tables in schema ingestion_platform to confluendo_app;

-- Staging-canary approval is recorded in ingestion_audit_log, then the live
-- runbook records the shipment ledger after the Vamo staging target commit.
-- Keep this scoped to the control-plane ledger tables; consumer target writes
-- use the separate vamo_canary_app role in the Vamo staging database.
grant insert, update on ingestion_platform.ingestion_targets to confluendo_app;
grant insert, update on ingestion_platform.ingestion_shipments to confluendo_app;
grant insert, delete on ingestion_platform.ingestion_shipment_items to confluendo_app;

grant update (
  status,
  error_code,
  error_message,
  started_at,
  updated_at
) on ingestion_platform.ingestion_tasks to confluendo_app;

grant update (
  status,
  released_at,
  release_reason
) on ingestion_platform.ingestion_worker_leases to confluendo_app;

grant insert on ingestion_platform.ingestion_audit_log to confluendo_app;

-- IP-18 batch scheduling mutates only Confluendo control-plane queue state.
-- It does not grant access to any consumer target database/table.
grant update (
  status,
  blockers,
  run_report,
  updated_at
) on ingestion_platform.ingestion_batch_queue_items to confluendo_app;

-- IP-18.4 batch dry-run execution writes only Confluendo control-plane
-- execution ledger rows. It does not grant access to any consumer database.
grant insert, update on ingestion_platform.ingestion_batch_dry_run_executions to confluendo_app;

-- IP-18.5 batch staging-canary wave approval writes only Confluendo control-plane
-- wave ledger rows and queue status updates. It does not grant consumer DB access.
grant insert, update on ingestion_platform.ingestion_batch_canary_waves to confluendo_app;
grant insert, update on ingestion_platform.ingestion_batch_canary_wave_items to confluendo_app;

-- IP-18.6.1 production package-wave ledger (control-plane only; no consumer DB grants)
grant insert, update on ingestion_platform.ingestion_batch_production_package_waves to confluendo_app;
grant insert, update on ingestion_platform.ingestion_batch_production_package_wave_items to confluendo_app;

-- IP-18.7 autonomy foundation: read policies; append/update cycle ledger rows.
-- Policy authoring remains owner-run — no INSERT/UPDATE on ingestion_autonomy_policies.
grant insert, update on ingestion_platform.ingestion_autonomy_runs to confluendo_app;
grant insert on ingestion_platform.ingestion_events to confluendo_app;

grant usage, select on all sequences in schema ingestion_platform to confluendo_app;

commit;

-- Optional first-admin seed.
--
-- After signing in once through /admin/sign-in, replace the email below with
-- your Supabase Auth email and run this block as the database owner.
--
-- insert into ingestion_platform.ingestion_admin_principals (
--   provider,
--   provider_user_id,
--   email,
--   role,
--   scopes,
--   mfa_required,
--   status,
--   created_by_provider,
--   created_by_provider_user_id
-- )
-- select
--   'supabase',
--   auth_user.id::text,
--   auth_user.email,
--   'admin',
--   array['vamo'],
--   true,
--   'active',
--   'bootstrap',
--   'bootstrap'
-- from auth.users auth_user
-- where lower(auth_user.email) = lower('YOUR_ADMIN_EMAIL@example.com')
-- on conflict (provider, provider_user_id) do update
-- set
--   email = excluded.email,
--   role = excluded.role,
--   scopes = excluded.scopes,
--   mfa_required = excluded.mfa_required,
--   status = excluded.status;
