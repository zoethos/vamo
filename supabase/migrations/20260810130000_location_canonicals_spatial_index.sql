-- Add spatial projections and resolver indexes without changing the established
-- Confluendo inbox contract or the public location table names.

create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;

alter table public.location_canonicals
  add constraint location_canonicals_coordinate_pair_check
  check ((latitude is null) = (longitude is null)) not valid;

alter table public.location_canonicals
  validate constraint location_canonicals_coordinate_pair_check;

alter table public.location_canonicals
  add constraint location_canonicals_municipality_coordinates_required
  check (
    feature_type <> 'municipality'
    or (latitude is not null and longitude is not null)
  ) not valid;

alter table public.location_canonicals
  validate constraint location_canonicals_municipality_coordinates_required;

alter table public.location_canonicals
  add column geom extensions.geography(point, 4326)
  generated always as (
    case
      when latitude is not null and longitude is not null
        then extensions.st_setsrid(
          extensions.st_makepoint(longitude, latitude),
          4326
        )::extensions.geography
      else null
    end
  ) stored;

comment on column public.location_canonicals.geom is
  'Generated WGS 84 geography point derived from shipment-declared longitude and latitude.';

create index location_canonicals_geom_gist
  on public.location_canonicals using gist (geom)
  where geom is not null;

create index location_canonicals_country_feature_lookup_idx
  on public.location_canonicals (country_code, feature_type, name_norm);

create index location_canonicals_name_norm_trgm_idx
  on public.location_canonicals using gin (name_norm extensions.gin_trgm_ops);
