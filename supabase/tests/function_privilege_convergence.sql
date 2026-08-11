\set ON_ERROR_STOP on

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role;
  end if;
end;
$$;

-- Reproduce Production's historical direct defaults before functions exist.
alter default privileges for role postgres in schema public
  grant execute on functions to anon, authenticated;

create table public.app_environment (
  singleton boolean primary key default true check (singleton),
  environment text not null check (environment in ('staging', 'production'))
);
insert into public.app_environment (environment) values ('staging');

create function public.current_app_environment()
returns table (environment text)
language plpgsql stable security definer set search_path = pg_catalog, public as $$
begin
  return query select configured.environment from public.app_environment configured where configured.singleton;
  if not found then
    raise exception 'Vamo app environment is not configured for this database';
  end if;
end;
$$;

create type public.member_role as enum ('owner');
create type public.budget_mode as enum ('none');
create type public.rsvp_status as enum ('going');

do $$
declare
  target_signature text;
  required_functions constant text[] := array[
    'public.accept_trip_close(uuid)',
    'public.amend_expense_conversion(uuid,bigint,numeric,text,numeric,boolean)',
    'public.can_edit_plan_item_scope(uuid,uuid)',
    'public.cancel_trip(uuid)',
    'public.capture_trip_fx_rate(uuid,character)',
    'public.clear_event_rsvp(uuid)',
    'public.commit_expense(uuid)',
    'public.create_subtrip(uuid,text,uuid[])',
    'public.create_trip(uuid,text,text,date,date,character)',
    'public.delete_trip(uuid)',
    'public.force_close_trip(uuid)',
    'public.get_trip_preview(text)',
    'public.insert_committed_expense(uuid,uuid,uuid,bigint,character,bigint,numeric,text,text,timestamp with time zone,text,double precision,double precision,timestamp with time zone,text,uuid,text,numeric,boolean,jsonb)',
    'public.is_subtrip_member(uuid)',
    'public.join_trip(text)',
    'public.mark_all_notifications_read()',
    'public.mark_notification_read(uuid)',
    'public.mark_trip_member_complete(uuid)',
    'public.object_to_trip_close(uuid,text)',
    'public.propose_expense(uuid,uuid,uuid,bigint,character,bigint,numeric,text,text,timestamp with time zone,text,numeric,boolean)',
    'public.register_push_device(text,text)',
    'public.reopen_from_soft_close(uuid)',
    'public.request_trip_close(uuid)',
    'public.respond_to_share(uuid,boolean,text)',
    'public.set_event_rsvp(uuid,public.rsvp_status)',
    'public.set_member_role(uuid,uuid,public.member_role)',
    'public.set_trip_background(uuid,text)',
    'public.set_trip_budget(uuid,public.budget_mode,bigint)',
    'public.stamp_close_notice_viewed(uuid)',
    'public.trip_committed_spend_cents(uuid)',
    'public.update_trip_dates(uuid,date,date)',
    'public.void_expense(uuid)',
    'public.withdraw_close_objection(uuid)',
    'public._apply_trip_fx_rate(uuid,character,numeric,text,uuid)',
    'public._apply_trip_theme(uuid,jsonb)',
    'public._enter_soft_close(uuid)',
    'public._stamp_member_close_notified(uuid,uuid)',
    'public.complete_service_usage_reservation(uuid)',
    'public.identity_integrity_summary()',
    'public.mark_close_reminder_sent(uuid,uuid)',
    'public.promote_location_aliases(integer)',
    'public.record_job_heartbeat(text,text)',
    'public.record_notification(uuid,uuid,text,text,text,text)',
    'public.record_premium_gate_notification(uuid,text,text)',
    'public.release_service_usage_reservation(uuid,text)',
    'public.reserve_service_usage(text,text,uuid)',
    'public.run_trip_lifecycle_jobs()',
    'public.s23_is_hex_color(text)',
    'public.s23_is_valid_theme_pack(jsonb)'
  ];
begin
  foreach target_signature in array required_functions loop
    execute format(
      'create function %s returns void language sql as %L',
      target_signature,
      'select;'
    );
  end loop;
end;
$$;

create table public.trips (id uuid, lifecycle text, close_requested_at timestamptz, close_warned_at timestamptz);
create table public.trip_members (trip_id uuid, user_id uuid, close_notified_at timestamptz);
create function public.unlisted_rpc() returns void language sql as 'select;';

\ir ../migrations/20260811140000_function_privilege_convergence.sql

do $$
begin
  if has_function_privilege('anon', 'public.unlisted_rpc()', 'execute')
    or has_function_privilege('authenticated', 'public.unlisted_rpc()', 'execute') then
    raise exception 'unlisted function remains callable';
  end if;
  if not has_function_privilege('anon', 'public.get_trip_preview(text)', 'execute') then
    raise exception 'anon preview access was not restored';
  end if;
  if not has_function_privilege('authenticated', 'public.create_trip(uuid,text,text,date,date,character)', 'execute') then
    raise exception 'authenticated RPC access was not restored';
  end if;
  if not has_function_privilege('service_role', 'public.run_trip_lifecycle_jobs()', 'execute') then
    raise exception 'service RPC access was not restored';
  end if;
  if to_regprocedure('public.rls_smoke_set_close_requested_at(uuid,timestamp with time zone)') is null
    or not has_function_privilege('service_role', 'public.rls_smoke_set_close_requested_at(uuid,timestamp with time zone)', 'execute') then
    raise exception 'staging fixture was not restored for service_role';
  end if;
end;
$$;

create function public.created_after_convergence() returns void language sql as 'select;';

do $$
begin
  if has_function_privilege('anon', 'public.created_after_convergence()', 'execute')
    or has_function_privilege('authenticated', 'public.created_after_convergence()', 'execute') then
    raise exception 'default privileges reopened anonymous or authenticated execution';
  end if;
end;
$$;

update public.app_environment set environment = 'production';
\ir ../migrations/20260811140000_function_privilege_convergence.sql

do $$
begin
  if to_regprocedure('public.rls_smoke_set_close_requested_at(uuid,timestamp with time zone)') is not null
    or to_regprocedure('public.rls_smoke_set_close_notified_at(uuid,uuid,timestamp with time zone)') is not null then
    raise exception 'production retained staging-only smoke fixtures';
  end if;
end;
$$;

delete from public.app_environment;

do $$
begin
  perform * from public.current_app_environment();
  raise exception 'unconfigured environment marker did not fail closed';
exception
  when sqlstate 'P0001' then null;
end;
$$;
