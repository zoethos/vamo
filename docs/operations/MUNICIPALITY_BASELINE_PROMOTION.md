# Municipality Baseline Promotion

Status: operator checklist for the municipality and additive spatial schema,
plus the consumer-owned inbox apply expansion. This is not authorization to
acquire or deliver a municipality release.

Related policy: [MIGRATION_PROMOTION_POLICY.md](MIGRATION_PROMOTION_POLICY.md).

Migration:

```text
supabase/migrations/20260810120000_municipality_place_baseline.sql
supabase/migrations/20260810130000_location_canonicals_spatial_index.sql
supabase/migrations/20260810140000_assert_municipality_feature_type_constraint.sql
```

Apply the files in this order. The final migration converges the known
feature-type constraint shapes and then fails closed if an unexpected
feature-type check remains. These application-schema migrations must be
promoted Staging first, then Production in the same release window. They create
no canary role, sentinel, or environment-specific object.

## Invariant

If it writes a product row, it must be a shipment item. The migration removes the earlier post-apply trigger shape: it does not create aliases or any other product rows outside `confluendo_inbox.shipment_items`. Municipality v1 has two explicit item kinds only: `location_canonicals` and `location_source_refs`.

`location_canonicals.geom` is a generated WGS 84 geography projection of the
declared latitude and longitude. It is not a shipment item or a second write
path. Municipalities require both coordinates; legacy non-municipality rows may
remain coordinate-less.

## Coordinate preflight

Before applying the spatial migration in each environment, run this read-only
query as the database owner. It must return zero rows; otherwise correct the
existing data before applying the batch.

```sql
select canonical_key, feature_type, latitude, longitude
from public.location_canonicals
where (latitude is null) <> (longitude is null)
   or (
     feature_type = 'municipality'
     and (latitude is null or longitude is null)
   );
```

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
  canonical.geom is not null as has_generated_geom,
  extensions.st_y(canonical.geom::extensions.geometry) as derived_latitude,
  extensions.st_x(canonical.geom::extensions.geometry) as derived_longitude,
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

select
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'location_canonicals_geom_gist'
  ) as has_geometry_index,
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'location_canonicals_country_feature_lookup_idx'
  ) as has_lookup_index,
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'location_canonicals_name_norm_trgm_idx'
  ) as has_trigram_index;

rollback;
```

Expected:

- `no_custom_shipment_item_trigger = true`.
- One `municipality` canonical with parent code `09`.
- `has_generated_geom = true`, `derived_latitude = 45.4642`, and
  `derived_longitude = 9.19`.
- All three index checks are true.
- One source reference with `smoke-2026-08`, `2026-08-01`, and `2026-12-31`.
- `applied_item_count = 2`; no aliases or other product rows are created.
- The rollback leaves no smoke shipment, inbox log, or product data.

## Production promotion

Apply the same exact migration to Vamo Production only after the Staging smoke passes. Run the same transactional smoke and record the result. Do not dispatch a municipality acquisition, Staging wave, delivery, or apply from this schema promotion alone.

Migration promotion checkpoint:

```text
- Migration files changed: supabase/migrations/20260810120000_municipality_place_baseline.sql, supabase/migrations/20260810130000_location_canonicals_spatial_index.sql, supabase/migrations/20260810140000_assert_municipality_feature_type_constraint.sql
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
# Municipality Baseline Promotion

## Extension checkpoint

The municipality migration batch enables the Supabase-supported PostGIS
extension in the shared `extensions` schema. This is a database-wide extension
change, not only a `location_canonicals` table change. Confirm that checkpoint
explicitly in both Staging and Production promotion records before proceeding
with the generated geography column and spatial indexes.
