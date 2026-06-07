-- S23 / R10 — AI theme resolver cache + guarded trip theme writer.
--
-- Production frontier already includes S25 as 0026. S22's old 0025 branch must
-- be renumbered when it resumes.

create table if not exists destination_themes (
  canonical_key text primary key,
  pack jsonb not null,
  display_name text not null,
  model text not null,
  schema_version int not null default 1,
  review_status text not null default 'auto'
    check (review_status in ('auto', 'reviewed', 'overridden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists destination_theme_aliases (
  alias text primary key,
  canonical_key text not null references destination_themes(canonical_key)
    on update cascade on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists provider_usage_events (
  id uuid primary key default gen_random_uuid(),
  feature text not null,
  provider text not null,
  model text,
  operation text not null,
  status text not null check (
    status in ('success', 'fallback', 'error', 'throttled', 'invalid_output')
  ),
  cached boolean not null default false,
  input_units int check (input_units is null or input_units >= 0),
  output_units int check (output_units is null or output_units >= 0),
  estimated_cost_usd numeric(12, 6)
    check (estimated_cost_usd is null or estimated_cost_usd >= 0),
  latency_ms int check (latency_ms is null or latency_ms >= 0),
  error_kind text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists destination_theme_aliases_canonical_idx
  on destination_theme_aliases(canonical_key);
create index if not exists provider_usage_events_feature_created_idx
  on provider_usage_events(feature, created_at desc);
create index if not exists provider_usage_events_provider_created_idx
  on provider_usage_events(provider, created_at desc);

alter table destination_themes enable row level security;
alter table destination_theme_aliases enable row level security;
alter table provider_usage_events enable row level security;

-- Supabase is moving toward explicit public-schema grants for Data API access.
-- Keep grants intentional even on projects that still have broad defaults.
revoke all on table destination_themes from anon, authenticated;
revoke all on table destination_theme_aliases from anon, authenticated;
revoke all on table provider_usage_events from anon, authenticated;

grant select on table destination_themes to authenticated;
grant select on table destination_theme_aliases to authenticated;

grant select, insert, update, delete on table destination_themes to service_role;
grant select, insert, update, delete on table destination_theme_aliases to service_role;
grant select, insert, update, delete on table provider_usage_events to service_role;

drop policy if exists destination_themes_authenticated_read on destination_themes;
create policy destination_themes_authenticated_read on destination_themes
  for select to authenticated using (true);

drop policy if exists destination_theme_aliases_authenticated_read
  on destination_theme_aliases;
create policy destination_theme_aliases_authenticated_read
  on destination_theme_aliases
  for select to authenticated using (true);

create or replace function s23_is_hex_color(p_value text) returns boolean
language sql immutable
as $$
  select coalesce(p_value, '') ~ '^#[0-9A-Fa-f]{6}$';
$$;

create or replace function s23_is_valid_theme_pack(p_theme jsonb)
returns boolean
language sql immutable
set search_path = public
as $$
  select
    jsonb_typeof(p_theme) = 'object'
    and p_theme ?& array[
      'id',
      'label',
      'gradient',
      'statBackground',
      'statPrimary',
      'statMuted',
      'accent',
      'memberBubble',
      'memberInitial',
      'tagline'
    ]
    and not exists (
      select 1
      from jsonb_object_keys(p_theme) as k(key)
      where k.key not in (
        'id',
        'label',
        'gradient',
        'statBackground',
        'statPrimary',
        'statMuted',
        'accent',
        'memberBubble',
        'memberInitial',
        'tagline'
      )
    )
    and coalesce(p_theme->>'id', '') ~ '^[a-z0-9][a-z0-9-]{0,63}$'
    and length(coalesce(p_theme->>'label', '')) between 1 and 40
    and case
      when jsonb_typeof(p_theme->'gradient') = 'array'
      then jsonb_array_length(p_theme->'gradient') between 2 and 3
        and not exists (
          select 1
          from jsonb_array_elements_text(p_theme->'gradient') as c(value)
          where not s23_is_hex_color(c.value)
        )
      else false
    end
    and s23_is_hex_color(p_theme->>'statBackground')
    and s23_is_hex_color(p_theme->>'statPrimary')
    and s23_is_hex_color(p_theme->>'statMuted')
    and s23_is_hex_color(p_theme->>'accent')
    and s23_is_hex_color(p_theme->>'memberBubble')
    and s23_is_hex_color(p_theme->>'memberInitial')
    and length(coalesce(p_theme->>'tagline', '')) between 1 and 16
    and strpos(coalesce(p_theme->>'tagline', ''), chr(10)) = 0
    and coalesce(p_theme->>'tagline', '') !~ '[0-9]'
    and coalesce(p_theme->>'tagline', '') !~* '(https?://|www\.)';
$$;

create or replace function _apply_trip_theme(
  p_trip_id uuid,
  p_theme jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_trip_id is null then
    raise exception 'trip id required';
  end if;
  if not s23_is_valid_theme_pack(p_theme) then
    raise exception 'invalid theme pack';
  end if;

  perform set_config('vamo.theme_rpc', '1', true);

  update trips
  set theme = p_theme
  where id = p_trip_id;

  if not found then
    raise exception 'trip not found';
  end if;
end;
$$;

revoke all on function s23_is_hex_color(text) from public;
revoke all on function s23_is_valid_theme_pack(jsonb) from public;
revoke all on function _apply_trip_theme(uuid, jsonb) from public;
grant execute on function s23_is_hex_color(text) to service_role;
grant execute on function s23_is_valid_theme_pack(jsonb) to service_role;
grant execute on function _apply_trip_theme(uuid, jsonb) to service_role;

-- Re-issue the current trip guard with the S23 theme write guard added.
create or replace function trips_update_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.theme is distinct from old.theme
     and coalesce(current_setting('vamo.theme_rpc', true), '') <> '1' then
    raise exception 'trip theme requires resolver';
  end if;

  if not is_trip_owner(old.id) then
    if new.owner_id is distinct from old.owner_id then
      raise exception 'only owner may change ownership';
    end if;
    if (new.lifecycle is distinct from old.lifecycle
       or new.closed_at is distinct from old.closed_at
       or new.closed_by is distinct from old.closed_by
       or new.cancelled_at is distinct from old.cancelled_at
       or new.cancelled_by is distinct from old.cancelled_by
       or new.close_requested_at is distinct from old.close_requested_at
       or new.close_warned_at is distinct from old.close_warned_at
       or new.unresolved_warned_at is distinct from old.unresolved_warned_at)
       and coalesce(current_setting('vamo.lifecycle_rpc', true), '') <> '1' then
      raise exception 'co-admin cannot change trip lifecycle';
    end if;
  end if;
  return new;
end;
$$;
