-- Read-only Confluendo production inbox telemetry role (IP-18.6.4).
--
-- Confluendo may poll apply status from confluendo_inbox only. This role must
-- never receive writer privileges or product-table access.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'confluendo_inbox_telemetry') then
    create role confluendo_inbox_telemetry
      nologin
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      nobypassrls;
  end if;
end;
$$;

comment on role confluendo_inbox_telemetry is
  'Read-only Confluendo production inbox telemetry. SELECT on confluendo_inbox tables only.';

grant usage on schema confluendo_inbox to confluendo_inbox_telemetry;
grant select on confluendo_inbox.shipments to confluendo_inbox_telemetry;
grant select on confluendo_inbox.shipment_items to confluendo_inbox_telemetry;
grant select on confluendo_inbox.apply_log to confluendo_inbox_telemetry;

revoke all on public.location_canonicals from confluendo_inbox_telemetry;
revoke all on public.location_source_refs from confluendo_inbox_telemetry;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'shipments'
      and policyname = 'confluendo_inbox_telemetry_shipments_select'
  ) then
    create policy confluendo_inbox_telemetry_shipments_select
      on confluendo_inbox.shipments
      for select
      to confluendo_inbox_telemetry
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'shipment_items'
      and policyname = 'confluendo_inbox_telemetry_items_select'
  ) then
    create policy confluendo_inbox_telemetry_items_select
      on confluendo_inbox.shipment_items
      for select
      to confluendo_inbox_telemetry
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'apply_log'
      and policyname = 'confluendo_inbox_telemetry_apply_log_select'
  ) then
    create policy confluendo_inbox_telemetry_apply_log_select
      on confluendo_inbox.apply_log
      for select
      to confluendo_inbox_telemetry
      using (true);
  end if;
end;
$$;

-- Supabase RLS evaluates the login role used by the pooler connection. The
-- password-bearing login role is provisioned outside this migration, so add
-- matching direct policies when it already exists. If the login role is created
-- after this migration, rerun this block after provisioning it.
do $$
begin
  if to_regrole('confluendo_inbox_telemetry_app') is not null then
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
  end if;
end;
$$;
