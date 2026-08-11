-- Converge public-function execution privileges across environments.
--
-- Production previously had direct anon/authenticated default grants. Revoke
-- every public entry point first, then restore the small, explicit RPC matrix.
-- The environment marker is intentionally required: staging retains the two
-- RLS smoke fixtures; production removes them.

alter default privileges for role postgres
  revoke execute on functions from public;

alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated;

do $$
declare
  function_oid oid;
  target_signature text;
  target_function regprocedure;
  authenticated_functions constant text[] := array[
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
    'public.withdraw_close_objection(uuid)'
  ];
  service_functions constant text[] := array[
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
  v_environment text;
begin
  for function_oid in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      function_oid::regprocedure
    );
  end loop;

  foreach target_signature in array authenticated_functions loop
    target_function := to_regprocedure(target_signature);
    if target_function is null then
      raise exception 'authenticated RPC is missing: %', target_signature;
    end if;
    execute format('grant execute on function %s to authenticated', target_function);
  end loop;

  target_function := to_regprocedure('public.get_trip_preview(text)');
  execute format('grant execute on function %s to anon', target_function);

  foreach target_signature in array service_functions loop
    target_function := to_regprocedure(target_signature);
    if target_function is null then
      raise exception 'service RPC is missing: %', target_signature;
    end if;
    execute format('grant execute on function %s to service_role', target_function);
  end loop;

  select environment into v_environment from public.current_app_environment();
  if v_environment = 'staging' then
    create or replace function public.rls_smoke_set_close_requested_at(
      p_trip_id uuid,
      p_at timestamptz
    ) returns void
    language plpgsql security definer set search_path = public as $fixture$
    begin
      perform set_config('vamo.lifecycle_rpc', '1', true);
      update trips
      set close_requested_at = p_at,
          close_warned_at = null
      where id = p_trip_id and lifecycle = 'closing';
    end;
    $fixture$;

    create or replace function public.rls_smoke_set_close_notified_at(
      p_trip_id uuid,
      p_user_id uuid,
      p_at timestamptz
    ) returns void
    language plpgsql security definer set search_path = public as $fixture$
    begin
      perform set_config('vamo.lifecycle_rpc', '1', true);
      update trip_members
      set close_notified_at = p_at
      where trip_id = p_trip_id and user_id = p_user_id;
    end;
    $fixture$;

    revoke all on function public.rls_smoke_set_close_requested_at(uuid, timestamptz)
      from public, anon, authenticated;
    revoke all on function public.rls_smoke_set_close_notified_at(uuid, uuid, timestamptz)
      from public, anon, authenticated;
    grant execute on function public.rls_smoke_set_close_requested_at(uuid, timestamptz)
      to service_role;
    grant execute on function public.rls_smoke_set_close_notified_at(uuid, uuid, timestamptz)
      to service_role;
  elsif v_environment = 'production' then
    drop function if exists public.rls_smoke_set_close_requested_at(uuid, timestamptz);
    drop function if exists public.rls_smoke_set_close_notified_at(uuid, uuid, timestamptz);
  else
    raise exception 'unsupported Vamo app environment: %', v_environment;
  end if;
end;
$$;

do $$
declare
  unexpected_access text;
  v_environment text;
begin
  select environment into v_environment from public.current_app_environment();

  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into unexpected_access
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind = 'f'
    and (
      has_function_privilege('anon', p.oid, 'execute')
      and p.oid <> 'public.get_trip_preview(text)'::regprocedure
      or has_function_privilege('authenticated', p.oid, 'execute')
      and p.oid not in (
        'public.accept_trip_close(uuid)'::regprocedure,
        'public.amend_expense_conversion(uuid,bigint,numeric,text,numeric,boolean)'::regprocedure,
        'public.can_edit_plan_item_scope(uuid,uuid)'::regprocedure,
        'public.cancel_trip(uuid)'::regprocedure,
        'public.capture_trip_fx_rate(uuid,character)'::regprocedure,
        'public.clear_event_rsvp(uuid)'::regprocedure,
        'public.commit_expense(uuid)'::regprocedure,
        'public.create_subtrip(uuid,text,uuid[])'::regprocedure,
        'public.create_trip(uuid,text,text,date,date,character)'::regprocedure,
        'public.delete_trip(uuid)'::regprocedure,
        'public.force_close_trip(uuid)'::regprocedure,
        'public.get_trip_preview(text)'::regprocedure,
        'public.insert_committed_expense(uuid,uuid,uuid,bigint,character,bigint,numeric,text,text,timestamp with time zone,text,double precision,double precision,timestamp with time zone,text,uuid,text,numeric,boolean,jsonb)'::regprocedure,
        'public.is_subtrip_member(uuid)'::regprocedure,
        'public.join_trip(text)'::regprocedure,
        'public.mark_all_notifications_read()'::regprocedure,
        'public.mark_notification_read(uuid)'::regprocedure,
        'public.mark_trip_member_complete(uuid)'::regprocedure,
        'public.object_to_trip_close(uuid,text)'::regprocedure,
        'public.propose_expense(uuid,uuid,uuid,bigint,character,bigint,numeric,text,text,timestamp with time zone,text,numeric,boolean)'::regprocedure,
        'public.register_push_device(text,text)'::regprocedure,
        'public.reopen_from_soft_close(uuid)'::regprocedure,
        'public.request_trip_close(uuid)'::regprocedure,
        'public.respond_to_share(uuid,boolean,text)'::regprocedure,
        'public.set_event_rsvp(uuid,public.rsvp_status)'::regprocedure,
        'public.set_member_role(uuid,uuid,public.member_role)'::regprocedure,
        'public.set_trip_background(uuid,text)'::regprocedure,
        'public.set_trip_budget(uuid,public.budget_mode,bigint)'::regprocedure,
        'public.stamp_close_notice_viewed(uuid)'::regprocedure,
        'public.trip_committed_spend_cents(uuid)'::regprocedure,
        'public.update_trip_dates(uuid,date,date)'::regprocedure,
        'public.void_expense(uuid)'::regprocedure,
        'public.withdraw_close_objection(uuid)'::regprocedure
      )
    );

  if unexpected_access is not null then
    raise exception 'public function privilege matrix did not converge: %', unexpected_access;
  end if;

  if v_environment = 'staging' and (
    to_regprocedure('public.rls_smoke_set_close_requested_at(uuid,timestamp with time zone)') is null
    or to_regprocedure('public.rls_smoke_set_close_notified_at(uuid,uuid,timestamp with time zone)') is null
    or not has_function_privilege('service_role', 'public.rls_smoke_set_close_requested_at(uuid,timestamp with time zone)', 'execute')
    or not has_function_privilege('service_role', 'public.rls_smoke_set_close_notified_at(uuid,uuid,timestamp with time zone)', 'execute')
  ) then
    raise exception 'staging RLS smoke fixtures did not converge';
  end if;

  if v_environment = 'production' and (
    to_regprocedure('public.rls_smoke_set_close_requested_at(uuid,timestamp with time zone)') is not null
    or to_regprocedure('public.rls_smoke_set_close_notified_at(uuid,uuid,timestamp with time zone)') is not null
  ) then
    raise exception 'production must not retain RLS smoke fixtures';
  end if;
end;
$$;
