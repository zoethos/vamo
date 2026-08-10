# Municipality Baseline Promotion

Status: operator checklist for the municipality schema and consumer-owned inbox apply expansion. This is not authorization to acquire or deliver a municipality release.

Related policy: [MIGRATION_PROMOTION_POLICY.md](MIGRATION_PROMOTION_POLICY.md).

Migration:

```text
supabase/migrations/20260810120000_municipality_place_baseline.sql
```

The migration is application schema and must be promoted Staging first, then Production in the same release window. It creates no canary role, sentinel, or environment-specific object.

## Invariant

If it writes a product row, it must be a shipment item. The migration removes the earlier post-apply trigger shape: it does not create aliases or any other product rows outside `confluendo_inbox.shipment_items`. Municipality v1 has two explicit item kinds only: `location_canonicals` and `location_source_refs`.

## Staging verification

After applying the exact migration to Vamo Staging, run this transactional acceptance smoke as the database owner. The inbox function deliberately requires a `production` shipment target. That protocol value is used below only inside the rolled-back Staging test; it does not select or write the Production database.

```sql
begin;

select not exists (
  select 1
  from pg_trigger
  where tgrelid = 'confluendo_inbox.shipment_items'::regclass
    and not tgisinternal
) as no_custom_shipment_item_trigger;

insert into confluendo_inbox.shipments (
  package_id, consumer_key, target_environment, schema_contract, status, checksum,
  source_manifest, attribution_manifest, diff_summary
) values (
  'smoke:municipality-baseline:apply', 'vamo', 'production',
  'vamo-place-intelligence@1', 'production_inbox_delivered', repeat('0', 64),
  '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
);

with items as (
  select
    'canonical'::text as item_key,
    'location_canonicals'::text as target_table,
    jsonb_build_object(
      'canonical_key', 'smoke-municipality-it',
      'display_name', 'Municipality smoke',
      'name_norm', 'municipality smoke',
      'feature_type', 'municipality',
      'country_code', 'IT',
      'administrative_parent_code', '09',
      'latitude', 45.4642,
      'longitude', 9.19,
      'source_provider', 'geonames',
      'source_place_id', 'smoke-municipality-it',
      'attribution', 'GeoNames, CC BY 4.0',
      'promotion_state', 'seeded'
    ) as payload
  union all
  select
    'source-ref',
    'location_source_refs',
    jsonb_build_object(
      'canonical_key', 'smoke-municipality-it',
      'provider', 'geonames',
      'source_place_id', 'smoke-municipality-it',
      'attribution', 'GeoNames, CC BY 4.0',
      'dataset_version', 'smoke-2026-08',
      'valid_from', '2026-08-01',
      'valid_to', '2026-12-31'
    )
)
insert into confluendo_inbox.shipment_items (
  package_id, item_key, target_table, operation, payload, payload_checksum
)
select
  'smoke:municipality-baseline:apply', item_key, target_table, 'upsert', payload,
  encode(extensions.digest(convert_to(payload::text, 'UTF8'), 'sha256'), 'hex')
from items;

update confluendo_inbox.shipments shipment
   set checksum = (
     select encode(
       extensions.digest(
         convert_to(
           string_agg(item_key || ':' || payload_checksum, E'\n' order by item_key),
           'UTF8'
         ),
         'sha256'
       ),
       'hex'
     )
     from confluendo_inbox.shipment_items
     where package_id = shipment.package_id
   )
 where package_id = 'smoke:municipality-baseline:apply';

select confluendo_inbox.apply_confluendo_shipment(
  'smoke:municipality-baseline:apply',
  'owner:municipality-baseline-smoke',
  'Verify direct, ledgered municipality metadata writes.'
);

select
  canonical.feature_type,
  canonical.administrative_parent_code,
  source_ref.dataset_version,
  source_ref.valid_from,
  source_ref.valid_to,
  (
    select count(*)
    from confluendo_inbox.shipment_items
    where package_id = 'smoke:municipality-baseline:apply'
      and apply_status = 'applied'
  ) as applied_item_count
from public.location_canonicals canonical
join public.location_source_refs source_ref on source_ref.canonical_id = canonical.id
where canonical.canonical_key = 'smoke-municipality-it'
  and source_ref.provider = 'geonames'
  and source_ref.source_place_id = 'smoke-municipality-it';

rollback;
```

Expected:

- `no_custom_shipment_item_trigger = true`.
- One `municipality` canonical with parent code `09`.
- One source reference with `smoke-2026-08`, `2026-08-01`, and `2026-12-31`.
- `applied_item_count = 2`; no aliases or other product rows are created.
- The rollback leaves no smoke shipment, inbox log, or product data.

## Production promotion

Apply the same exact migration to Vamo Production only after the Staging smoke passes. Run the same transactional smoke and record the result. Do not dispatch a municipality acquisition, Staging wave, delivery, or apply from this schema promotion alone.

Migration promotion checkpoint:

```text
- Migration files changed: supabase/migrations/20260810120000_municipality_place_baseline.sql
- Staging project/ref:
- Staging apply status:
- Staging verification/smoke:
- Production project/ref:
- Production apply status:
- Production verification:
- Current drift:
- If production not promoted: blocker, owner, planned date, and why drift is acceptable:
- Environment-specific objects excluded from production: none
```
