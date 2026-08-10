-- Production inbox telemetry identity reader (IP-18.6.4 follow-up).
--
-- The telemetry app login is provisioned as NOLOGIN here. A Vamo DBA enables
-- LOGIN and assigns its password only in Production after this shared schema is
-- applied. It may read inbox apply facts and the narrow identity readers; it
-- cannot invoke Vamo apply, read the marker table, or write product tables.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'confluendo_inbox_telemetry_app') then
    create role confluendo_inbox_telemetry_app
      nologin
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      nobypassrls;
  end if;
end;
$$;

comment on role confluendo_inbox_telemetry_app is
  'Production-only login shell for read-only Confluendo inbox telemetry and environment receipt verification.';

grant usage on schema confluendo_inbox to confluendo_inbox_telemetry_app;
grant select on confluendo_inbox.shipments to confluendo_inbox_telemetry_app;
grant select on confluendo_inbox.shipment_items to confluendo_inbox_telemetry_app;
grant select on confluendo_inbox.apply_log to confluendo_inbox_telemetry_app;
grant execute on function public.current_app_environment() to confluendo_inbox_telemetry_app;
grant execute on function confluendo_inbox.current_consumer_identity() to confluendo_inbox_telemetry_app;

revoke all on public.app_environment from confluendo_inbox_telemetry_app;
revoke all on public.location_canonicals from confluendo_inbox_telemetry_app;
revoke all on public.location_source_refs from confluendo_inbox_telemetry_app;
revoke execute on function confluendo_inbox.apply_confluendo_shipment(text, text, text)
  from confluendo_inbox_telemetry_app;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'shipments'
      and policyname = 'confluendo_inbox_telemetry_app_shipments_select'
  ) then
    create policy confluendo_inbox_telemetry_app_shipments_select
      on confluendo_inbox.shipments
      for select
      to confluendo_inbox_telemetry_app
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'shipment_items'
      and policyname = 'confluendo_inbox_telemetry_app_items_select'
  ) then
    create policy confluendo_inbox_telemetry_app_items_select
      on confluendo_inbox.shipment_items
      for select
      to confluendo_inbox_telemetry_app
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'apply_log'
      and policyname = 'confluendo_inbox_telemetry_app_apply_log_select'
  ) then
    create policy confluendo_inbox_telemetry_app_apply_log_select
      on confluendo_inbox.apply_log
      for select
      to confluendo_inbox_telemetry_app
      using (true);
  end if;
end;
$$;
