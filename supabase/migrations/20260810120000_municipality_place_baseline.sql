-- Municipality place-data baseline.
--
-- Administrative releases retain their source authority identifier through
-- location_source_refs and preserve the dataset/version/validity facts that
-- make a municipality reference auditable. Existing POI shipments remain
-- compatible because every new field is optional.

do $$
declare
  v_constraint_name name;
begin
  select conname
    into v_constraint_name
    from pg_constraint
   where conrelid = 'public.location_canonicals'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) like '%feature_type%'
   order by conname
   limit 1;

  if v_constraint_name is not null then
    execute format(
      'alter table public.location_canonicals drop constraint %I',
      v_constraint_name
    );
  end if;
end;
$$;

alter table public.location_canonicals
  add constraint location_canonicals_feature_type_allowed
  check (
    feature_type in (
      'country',
      'region',
      'municipality',
      'locality',
      'neighborhood',
      'poi',
      'landmark',
      'address',
      'unknown'
    )
  );

alter table public.location_canonicals
  add column if not exists administrative_parent_code text;

comment on column public.location_canonicals.administrative_parent_code is
  'Source-declared parent administrative code for a governed municipality reference. It is not user observation data.';

alter table public.location_source_refs
  add column if not exists dataset_version text,
  add column if not exists valid_from date,
  add column if not exists valid_to date;

alter table public.location_source_refs
  add constraint location_source_refs_validity_period_check
  check (valid_from is null or valid_to is null or valid_from <= valid_to);

comment on column public.location_source_refs.dataset_version is
  'Source dataset or release version that supplied this reference.';

comment on column public.location_source_refs.valid_from is
  'Inclusive source-declared validity date, when the source provides one.';

comment on column public.location_source_refs.valid_to is
  'Inclusive source-declared validity end date, when the source provides one.';

drop trigger if exists confluendo_inbox_apply_administrative_reference_metadata
  on confluendo_inbox.shipment_items;

drop function if exists confluendo_inbox.apply_administrative_reference_metadata();

-- Every product-table mutation made by this consumer boundary is represented by
-- its own checksum-protected shipment item. Do not add post-apply triggers that
-- create product rows outside the approved and receipted item ledger.
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
          administrative_parent_code,
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
          nullif(v_item.payload->>'administrative_parent_code', ''),
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
          administrative_parent_code = case
            when v_item.payload ? 'administrative_parent_code'
              then excluded.administrative_parent_code
            else public.location_canonicals.administrative_parent_code
          end,
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
          expires_at,
          dataset_version,
          valid_from,
          valid_to
        ) values (
          v_canonical_id,
          v_item.payload->>'provider',
          v_item.payload->>'source_place_id',
          nullif(v_item.payload->>'source_payload_hash', ''),
          v_item.payload->>'attribution',
          coalesce((v_item.payload->>'fetched_at')::timestamptz, now()),
          case when v_item.payload ? 'expires_at' then (v_item.payload->>'expires_at')::timestamptz else null end,
          nullif(v_item.payload->>'dataset_version', ''),
          case when nullif(v_item.payload->>'valid_from', '') is not null
            then (v_item.payload->>'valid_from')::date else null end,
          case when nullif(v_item.payload->>'valid_to', '') is not null
            then (v_item.payload->>'valid_to')::date else null end
        )
        on conflict (provider, source_place_id) do update set
          canonical_id = excluded.canonical_id,
          source_payload_hash = excluded.source_payload_hash,
          attribution = excluded.attribution,
          fetched_at = excluded.fetched_at,
          expires_at = excluded.expires_at,
          dataset_version = case
            when v_item.payload ? 'dataset_version' then excluded.dataset_version
            else public.location_source_refs.dataset_version
          end,
          valid_from = case
            when v_item.payload ? 'valid_from' then excluded.valid_from
            else public.location_source_refs.valid_from
          end,
          valid_to = case
            when v_item.payload ? 'valid_to' then excluded.valid_to
            else public.location_source_refs.valid_to
          end;
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

comment on function confluendo_inbox.apply_confluendo_shipment(text, text, text) is
  'Vamo-owned consumer inbox apply boundary. Every product-table mutation must be represented by a checksum-protected shipment item.';
