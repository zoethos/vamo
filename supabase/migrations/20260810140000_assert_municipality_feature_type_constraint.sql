-- Converge the municipality feature-type constraint, then fail closed if an
-- unexpected check remains. This is intentionally additive: it repairs the
-- known baseline shapes without rewriting the preceding migration.

do $$
declare
  v_constraint_name name;
begin
  for v_constraint_name in
    select conname
    from pg_constraint
   where conrelid = 'public.location_canonicals'::regclass
     and contype = 'c'
     and conname in (
       'location_canonicals_feature_type_check',
       'location_canonicals_feature_type_allowed'
     )
  loop
    execute format(
      'alter table public.location_canonicals drop constraint %I',
      v_constraint_name
    );
  end loop;
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

do $$
declare
  v_feature_type_definition text;
  v_unexpected_constraint_names text;
begin
  select pg_get_constraintdef(oid)
    into v_feature_type_definition
    from pg_constraint
   where conrelid = 'public.location_canonicals'::regclass
     and contype = 'c'
     and conname = 'location_canonicals_feature_type_allowed';

  if v_feature_type_definition is null
     or position('municipality' in lower(v_feature_type_definition)) = 0 then
    raise exception
      'location_canonicals feature_type constraint did not converge to the municipality-allowing form';
  end if;

  select string_agg(conname, ', ' order by conname)
    into v_unexpected_constraint_names
    from pg_constraint
   where conrelid = 'public.location_canonicals'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%feature_type%'
     and conname not in (
       'location_canonicals_feature_type_allowed',
       'location_canonicals_municipality_coordinates_required'
     );

  if v_unexpected_constraint_names is not null then
    raise exception
      'location_canonicals has unexpected feature_type constraint(s): %',
      v_unexpected_constraint_names;
  end if;
end;
$$;
