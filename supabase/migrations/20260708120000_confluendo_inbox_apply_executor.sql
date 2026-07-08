-- Least-privilege Confluendo production inbox apply role (IP-18.6.6).
--
-- Confluendo may invoke Vamo's apply_confluendo_shipment boundary and read inbox
-- state for preflight/result display. This role must never receive writer
-- delivery privileges or direct product-table access.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'confluendo_inbox_apply') then
    create role confluendo_inbox_apply
      nologin
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      nobypassrls;
  end if;
end;
$$;

comment on role confluendo_inbox_apply is
  'Confluendo production inbox apply executor. EXECUTE on apply_confluendo_shipment and SELECT on inbox tables only.';

grant usage on schema confluendo_inbox to confluendo_inbox_apply;
grant select on confluendo_inbox.shipments to confluendo_inbox_apply;
grant select on confluendo_inbox.shipment_items to confluendo_inbox_apply;
grant select on confluendo_inbox.apply_log to confluendo_inbox_apply;
grant execute on function confluendo_inbox.apply_confluendo_shipment(text, text, text)
  to confluendo_inbox_apply;

revoke all on public.location_canonicals from confluendo_inbox_apply;
revoke all on public.location_source_refs from confluendo_inbox_apply;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'shipments'
      and policyname = 'confluendo_inbox_apply_shipments_select'
  ) then
    create policy confluendo_inbox_apply_shipments_select
      on confluendo_inbox.shipments
      for select
      to confluendo_inbox_apply
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'shipment_items'
      and policyname = 'confluendo_inbox_apply_items_select'
  ) then
    create policy confluendo_inbox_apply_items_select
      on confluendo_inbox.shipment_items
      for select
      to confluendo_inbox_apply
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'apply_log'
      and policyname = 'confluendo_inbox_apply_apply_log_select'
  ) then
    create policy confluendo_inbox_apply_apply_log_select
      on confluendo_inbox.apply_log
      for select
      to confluendo_inbox_apply
      using (true);
  end if;
end;
$$;

do $$
begin
  if to_regrole('confluendo_inbox_apply_app') is not null then
    if not exists (
      select 1 from pg_policies
      where schemaname = 'confluendo_inbox'
        and tablename = 'shipments'
        and policyname = 'confluendo_inbox_apply_app_shipments_select'
    ) then
      create policy confluendo_inbox_apply_app_shipments_select
        on confluendo_inbox.shipments
        for select
        to confluendo_inbox_apply_app
        using (true);
    end if;

    if not exists (
      select 1 from pg_policies
      where schemaname = 'confluendo_inbox'
        and tablename = 'shipment_items'
        and policyname = 'confluendo_inbox_apply_app_items_select'
    ) then
      create policy confluendo_inbox_apply_app_items_select
        on confluendo_inbox.shipment_items
        for select
        to confluendo_inbox_apply_app
        using (true);
    end if;

    if not exists (
      select 1 from pg_policies
      where schemaname = 'confluendo_inbox'
        and tablename = 'apply_log'
        and policyname = 'confluendo_inbox_apply_app_apply_log_select'
    ) then
      create policy confluendo_inbox_apply_app_apply_log_select
        on confluendo_inbox.apply_log
        for select
        to confluendo_inbox_apply_app
        using (true);
    end if;
  end if;
end;
$$;
