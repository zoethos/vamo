-- Confluendo production inbox contract for Vamo.
--
-- This is the consumer-owned boundary for IP-17. Confluendo may deliver
-- approved packages into confluendo_inbox, but it must never receive direct
-- privileges on Vamo product tables. Vamo applies packages through the
-- security-definer function below.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists confluendo_inbox;

comment on schema confluendo_inbox is
  'Vamo-owned inbox for Confluendo shipment packages. Browser roles have no access.';

create table if not exists confluendo_inbox.shipments (
  package_id text primary key,
  consumer_key text not null,
  target_environment text not null
    check (target_environment in ('staging', 'production')),
  schema_contract text not null,
  status text not null
    check (
      status in (
        'production_inbox_delivered',
        'production_inbox_delivery_failed',
        'consumer_apply_pending',
        'consumer_applied',
        'consumer_apply_failed'
      )
    ),
  checksum text not null,
  source_manifest jsonb not null,
  attribution_manifest jsonb not null,
  diff_summary jsonb not null,
  approved_by text,
  approval_reason text,
  delivered_at timestamptz not null default now(),
  applied_at timestamptz
);

comment on table confluendo_inbox.shipments is
  'Package-level Confluendo delivery ledger. Delivery is not the same as Vamo product apply.';
comment on column confluendo_inbox.shipments.checksum is
  'Package checksum: sha256 over newline-joined item_key:payload_checksum pairs ordered by item_key.';

create table if not exists confluendo_inbox.shipment_items (
  package_id text not null
    references confluendo_inbox.shipments(package_id) on delete cascade,
  item_key text not null,
  target_table text not null
    check (target_table in ('location_canonicals', 'location_source_refs')),
  operation text not null
    check (operation in ('upsert', 'delete')),
  payload jsonb not null,
  payload_checksum text not null,
  apply_status text not null default 'pending'
    check (apply_status in ('pending', 'applied', 'skipped', 'rejected')),
  apply_error text,
  primary key (package_id, item_key)
);

comment on table confluendo_inbox.shipment_items is
  'Generic JSONB inbox rows. Vamo validates shape during apply before touching product tables.';
comment on column confluendo_inbox.shipment_items.payload_checksum is
  'Payload checksum: sha256 over Postgres jsonb::text canonical representation.';

create table if not exists confluendo_inbox.apply_log (
  id uuid primary key default extensions.gen_random_uuid(),
  package_id text not null,
  item_key text,
  result text not null
    check (result in ('applied', 'skipped', 'rejected', 'consumer_applied', 'consumer_apply_failed')),
  detail text,
  applied_at timestamptz not null default now()
);

comment on table confluendo_inbox.apply_log is
  'Vamo-owned apply audit log, including per-row outcomes and package-level diagnostics.';

alter table confluendo_inbox.shipments enable row level security;
alter table confluendo_inbox.shipment_items enable row level security;
alter table confluendo_inbox.apply_log enable row level security;

revoke all on schema confluendo_inbox from public;
revoke all on confluendo_inbox.shipments from public, anon, authenticated;
revoke all on confluendo_inbox.shipment_items from public, anon, authenticated;
revoke all on confluendo_inbox.apply_log from public, anon, authenticated;

grant usage on schema confluendo_inbox to service_role;
grant all privileges on confluendo_inbox.shipments to service_role;
grant all privileges on confluendo_inbox.shipment_items to service_role;
grant all privileges on confluendo_inbox.apply_log to service_role;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'confluendo_inbox_writer') then
    create role confluendo_inbox_writer
      nologin
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      nobypassrls;
  else
    alter role confluendo_inbox_writer
      nologin
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      nobypassrls;
  end if;
end;
$$;

comment on role confluendo_inbox_writer is
  'Least-privilege Confluendo production inbox writer. No product-table privileges, no ownership, no create/alter, no role admin, no RLS bypass.';

grant usage on schema confluendo_inbox to confluendo_inbox_writer;
grant select, insert on confluendo_inbox.shipments to confluendo_inbox_writer;
grant update (status) on confluendo_inbox.shipments to confluendo_inbox_writer;
grant select, insert on confluendo_inbox.shipment_items to confluendo_inbox_writer;

revoke all on public.location_canonicals from confluendo_inbox_writer;
revoke all on public.location_source_refs from confluendo_inbox_writer;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'shipments'
      and policyname = 'confluendo_inbox_writer_shipments_select'
  ) then
    create policy confluendo_inbox_writer_shipments_select
      on confluendo_inbox.shipments
      for select
      to confluendo_inbox_writer
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'shipments'
      and policyname = 'confluendo_inbox_writer_shipments_insert'
  ) then
    create policy confluendo_inbox_writer_shipments_insert
      on confluendo_inbox.shipments
      for insert
      to confluendo_inbox_writer
      with check (
        target_environment = 'production'
        and status = 'production_inbox_delivered'
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'shipments'
      and policyname = 'confluendo_inbox_writer_shipments_update'
  ) then
    create policy confluendo_inbox_writer_shipments_update
      on confluendo_inbox.shipments
      for update
      to confluendo_inbox_writer
      using (true)
      with check (
        status in (
          'production_inbox_delivered',
          'production_inbox_delivery_failed'
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'shipment_items'
      and policyname = 'confluendo_inbox_writer_items_select'
  ) then
    create policy confluendo_inbox_writer_items_select
      on confluendo_inbox.shipment_items
      for select
      to confluendo_inbox_writer
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'confluendo_inbox'
      and tablename = 'shipment_items'
      and policyname = 'confluendo_inbox_writer_items_insert'
  ) then
    create policy confluendo_inbox_writer_items_insert
      on confluendo_inbox.shipment_items
      for insert
      to confluendo_inbox_writer
      with check (
        exists (
          select 1
          from confluendo_inbox.shipments s
          where s.package_id = shipment_items.package_id
            and s.target_environment = 'production'
            and s.status = 'production_inbox_delivered'
        )
      );
  end if;
end;
$$;

create or replace function confluendo_inbox.apply_confluendo_shipment(
  p_package_id text,
  p_approved_by text,
  p_approval_reason text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, confluendo_inbox, public
as $$
declare
  v_supported_contract constant text := 'vamo-place-intelligence@1';
  v_shipment confluendo_inbox.shipments%rowtype;
  v_expected_package_checksum text;
  v_bad_payload_count integer;
  v_delete_count integer;
  v_item_count integer;
  v_item record;
  v_canonical_id uuid;
  v_applied integer := 0;
  v_skipped integer := 0;
  v_rejected integer := 0;
  v_error text;
begin
  select *
    into v_shipment
    from confluendo_inbox.shipments
   where package_id = p_package_id
   for update;

  if not found then
    raise exception 'Confluendo shipment package % not found', p_package_id
      using errcode = 'P0002';
  end if;

  if v_shipment.applied_at is not null then
    return jsonb_build_object(
      'package_id', p_package_id,
      'applied', 0,
      'skipped', 1,
      'rejected', 0,
      'status', v_shipment.status
    );
  end if;

  if nullif(trim(coalesce(p_approved_by, '')), '') is null then
    update confluendo_inbox.shipments
       set status = 'consumer_apply_failed'
     where package_id = p_package_id;
    insert into confluendo_inbox.apply_log (package_id, result, detail)
    values (p_package_id, 'rejected', 'approved_by is required');
    return jsonb_build_object(
      'package_id', p_package_id,
      'applied', 0,
      'skipped', 0,
      'rejected', 1,
      'status', 'consumer_apply_failed',
      'error', 'approved_by_required'
    );
  end if;

  if nullif(trim(coalesce(p_approval_reason, '')), '') is null then
    update confluendo_inbox.shipments
       set status = 'consumer_apply_failed'
     where package_id = p_package_id;
    insert into confluendo_inbox.apply_log (package_id, result, detail)
    values (p_package_id, 'rejected', 'approval_reason is required');
    return jsonb_build_object(
      'package_id', p_package_id,
      'applied', 0,
      'skipped', 0,
      'rejected', 1,
      'status', 'consumer_apply_failed',
      'error', 'approval_reason_required'
    );
  end if;

  if v_shipment.target_environment <> 'production' then
    update confluendo_inbox.shipments
       set status = 'consumer_apply_failed'
     where package_id = p_package_id;
    insert into confluendo_inbox.apply_log (package_id, result, detail)
    values (p_package_id, 'rejected', 'target_environment must be production');
    return jsonb_build_object(
      'package_id', p_package_id,
      'applied', 0,
      'skipped', 0,
      'rejected', 1,
      'status', 'consumer_apply_failed',
      'error', 'non_production_target'
    );
  end if;

  if v_shipment.status <> 'production_inbox_delivered' then
    update confluendo_inbox.shipments
       set status = 'consumer_apply_failed'
     where package_id = p_package_id;
    insert into confluendo_inbox.apply_log (package_id, result, detail)
    values (p_package_id, 'rejected', 'shipment status must be production_inbox_delivered');
    return jsonb_build_object(
      'package_id', p_package_id,
      'applied', 0,
      'skipped', 0,
      'rejected', 1,
      'status', 'consumer_apply_failed',
      'error', 'invalid_shipment_status'
    );
  end if;

  if v_shipment.schema_contract <> v_supported_contract then
    update confluendo_inbox.shipments
       set status = 'consumer_apply_failed'
     where package_id = p_package_id;
    insert into confluendo_inbox.apply_log (package_id, result, detail)
    values (
      p_package_id,
      'rejected',
      format('schema_contract %s is not supported', v_shipment.schema_contract)
    );
    return jsonb_build_object(
      'package_id', p_package_id,
      'applied', 0,
      'skipped', 0,
      'rejected', 1,
      'status', 'consumer_apply_failed',
      'error', 'unsupported_schema_contract'
    );
  end if;

  select count(*)::integer
    into v_item_count
    from confluendo_inbox.shipment_items
   where package_id = p_package_id;

  if v_item_count = 0 then
    update confluendo_inbox.shipments
       set status = 'consumer_apply_failed'
     where package_id = p_package_id;
    insert into confluendo_inbox.apply_log (package_id, result, detail)
    values (p_package_id, 'rejected', 'shipment has no items');
    return jsonb_build_object(
      'package_id', p_package_id,
      'applied', 0,
      'skipped', 0,
      'rejected', 1,
      'status', 'consumer_apply_failed',
      'error', 'empty_package'
    );
  end if;

  select count(*)::integer
    into v_bad_payload_count
    from confluendo_inbox.shipment_items
   where package_id = p_package_id
     and payload_checksum <> encode(
       extensions.digest(convert_to(payload::text, 'UTF8'), 'sha256'),
       'hex'
     );

  if v_bad_payload_count > 0 then
    update confluendo_inbox.shipments
       set status = 'consumer_apply_failed'
     where package_id = p_package_id;
    update confluendo_inbox.shipment_items
       set apply_status = 'rejected',
           apply_error = 'payload_checksum_mismatch'
     where package_id = p_package_id;
    insert into confluendo_inbox.apply_log (package_id, result, detail)
    values (p_package_id, 'rejected', 'one or more payload checksums do not match payload::text');
    return jsonb_build_object(
      'package_id', p_package_id,
      'applied', 0,
      'skipped', 0,
      'rejected', v_bad_payload_count,
      'status', 'consumer_apply_failed',
      'error', 'payload_checksum_mismatch'
    );
  end if;

  select encode(
           extensions.digest(
             convert_to(
               coalesce(string_agg(item_key || ':' || payload_checksum, E'\n' order by item_key), ''),
               'UTF8'
             ),
             'sha256'
           ),
           'hex'
         )
    into v_expected_package_checksum
    from confluendo_inbox.shipment_items
   where package_id = p_package_id;

  if v_expected_package_checksum <> v_shipment.checksum then
    update confluendo_inbox.shipments
       set status = 'consumer_apply_failed'
     where package_id = p_package_id;
    insert into confluendo_inbox.apply_log (package_id, result, detail)
    values (p_package_id, 'rejected', 'package checksum mismatch');
    return jsonb_build_object(
      'package_id', p_package_id,
      'applied', 0,
      'skipped', 0,
      'rejected', 1,
      'status', 'consumer_apply_failed',
      'error', 'package_checksum_mismatch'
    );
  end if;

  select count(*)::integer
    into v_delete_count
    from confluendo_inbox.shipment_items
   where package_id = p_package_id
     and operation = 'delete';

  if v_delete_count > 0 then
    update confluendo_inbox.shipments
       set status = 'consumer_apply_failed'
     where package_id = p_package_id;
    update confluendo_inbox.shipment_items
       set apply_status = 'rejected',
           apply_error = 'delete_not_supported'
     where package_id = p_package_id
       and operation = 'delete';
    insert into confluendo_inbox.apply_log (package_id, result, detail)
    values (p_package_id, 'rejected', 'delete operations are not supported by this apply function');
    return jsonb_build_object(
      'package_id', p_package_id,
      'applied', 0,
      'skipped', 0,
      'rejected', v_delete_count,
      'status', 'consumer_apply_failed',
      'error', 'delete_not_supported'
    );
  end if;

  begin
    update confluendo_inbox.shipments
       set status = 'consumer_apply_pending',
           approved_by = p_approved_by,
           approval_reason = p_approval_reason
     where package_id = p_package_id;

    for v_item in
      select *
        from confluendo_inbox.shipment_items
       where package_id = p_package_id
       order by
         case target_table
           when 'location_canonicals' then 1
           when 'location_source_refs' then 2
           else 99
         end,
         item_key
    loop
      if v_item.operation <> 'upsert' then
        raise exception 'Unsupported operation % for item %', v_item.operation, v_item.item_key;
      end if;

      if v_item.target_table = 'location_canonicals' then
        insert into public.location_canonicals (
          canonical_key,
          display_name,
          name_norm,
          feature_type,
          country_code,
          admin1,
          latitude,
          longitude,
          source_provider,
          source_place_id,
          source_rank,
          attribution,
          confidence,
          promotion_state,
          updated_at
        ) values (
          v_item.payload->>'canonical_key',
          v_item.payload->>'display_name',
          v_item.payload->>'name_norm',
          coalesce(v_item.payload->>'feature_type', 'unknown'),
          nullif(v_item.payload->>'country_code', ''),
          nullif(v_item.payload->>'admin1', ''),
          case when v_item.payload ? 'latitude' then (v_item.payload->>'latitude')::double precision else null end,
          case when v_item.payload ? 'longitude' then (v_item.payload->>'longitude')::double precision else null end,
          v_item.payload->>'source_provider',
          nullif(v_item.payload->>'source_place_id', ''),
          coalesce((v_item.payload->>'source_rank')::integer, 100),
          v_item.payload->>'attribution',
          coalesce((v_item.payload->>'confidence')::numeric, 0.5000),
          coalesce(v_item.payload->>'promotion_state', 'pending_review'),
          now()
        )
        on conflict (canonical_key) do update set
          display_name = excluded.display_name,
          name_norm = excluded.name_norm,
          feature_type = excluded.feature_type,
          country_code = excluded.country_code,
          admin1 = excluded.admin1,
          latitude = excluded.latitude,
          longitude = excluded.longitude,
          source_provider = excluded.source_provider,
          source_place_id = excluded.source_place_id,
          source_rank = excluded.source_rank,
          attribution = excluded.attribution,
          confidence = excluded.confidence,
          promotion_state = excluded.promotion_state,
          updated_at = now()
        returning id into v_canonical_id;
      elsif v_item.target_table = 'location_source_refs' then
        select id
          into v_canonical_id
          from public.location_canonicals
         where canonical_key = v_item.payload->>'canonical_key';

        if v_canonical_id is null then
          raise exception 'No canonical found for item % canonical_key %',
            v_item.item_key,
            v_item.payload->>'canonical_key';
        end if;

        insert into public.location_source_refs (
          canonical_id,
          provider,
          source_place_id,
          source_payload_hash,
          attribution,
          fetched_at,
          expires_at
        ) values (
          v_canonical_id,
          v_item.payload->>'provider',
          v_item.payload->>'source_place_id',
          nullif(v_item.payload->>'source_payload_hash', ''),
          v_item.payload->>'attribution',
          coalesce((v_item.payload->>'fetched_at')::timestamptz, now()),
          case when v_item.payload ? 'expires_at' then (v_item.payload->>'expires_at')::timestamptz else null end
        )
        on conflict (provider, source_place_id) do update set
          canonical_id = excluded.canonical_id,
          source_payload_hash = excluded.source_payload_hash,
          attribution = excluded.attribution,
          fetched_at = excluded.fetched_at,
          expires_at = excluded.expires_at;
      else
        raise exception 'Unsupported target_table % for item %', v_item.target_table, v_item.item_key;
      end if;

      update confluendo_inbox.shipment_items
         set apply_status = 'applied',
             apply_error = null
       where package_id = p_package_id
         and item_key = v_item.item_key;

      insert into confluendo_inbox.apply_log (package_id, item_key, result, detail)
      values (p_package_id, v_item.item_key, 'applied', v_item.target_table || ' upserted');

      v_applied := v_applied + 1;
    end loop;

    update confluendo_inbox.shipments
       set status = 'consumer_applied',
           applied_at = now()
     where package_id = p_package_id;

    insert into confluendo_inbox.apply_log (package_id, result, detail)
    values (p_package_id, 'consumer_applied', 'shipment applied successfully');

    return jsonb_build_object(
      'package_id', p_package_id,
      'applied', v_applied,
      'skipped', v_skipped,
      'rejected', v_rejected,
      'status', 'consumer_applied'
    );
  exception
    when others then
      get stacked diagnostics v_error = message_text;

      update confluendo_inbox.shipments
         set status = 'consumer_apply_failed'
       where package_id = p_package_id;

      update confluendo_inbox.shipment_items
         set apply_status = 'rejected',
             apply_error = v_error
       where package_id = p_package_id
         and apply_status = 'pending';

      insert into confluendo_inbox.apply_log (package_id, result, detail)
      values (p_package_id, 'consumer_apply_failed', v_error);

      return jsonb_build_object(
        'package_id', p_package_id,
        'applied', 0,
        'skipped', 0,
        'rejected', greatest(v_item_count, 1),
        'status', 'consumer_apply_failed',
        'error', v_error
      );
  end;
end;
$$;

revoke all on function confluendo_inbox.apply_confluendo_shipment(text, text, text) from public;
revoke all on function confluendo_inbox.apply_confluendo_shipment(text, text, text) from anon, authenticated;
grant execute on function confluendo_inbox.apply_confluendo_shipment(text, text, text) to service_role;

comment on function confluendo_inbox.apply_confluendo_shipment(text, text, text) is
  'Vamo-owned production inbox apply boundary. Confluendo delivers packages only; Vamo applies them.';
