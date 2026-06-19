-- S49 C-light — plan metadata + data-driven capabilities spine.
--
-- Intentionally keep `plan_item_kind` as a Postgres enum. Future slices that
-- need new kinds should add them with a standalone `ALTER TYPE ... ADD VALUE`
-- migration before using the value in tables or seeds.

alter table public.trip_plan_items
  add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.trip_plan_items
  drop constraint if exists trip_plan_items_metadata_object_chk;

alter table public.trip_plan_items
  add constraint trip_plan_items_metadata_object_chk
  check (jsonb_typeof(metadata) = 'object');

create table if not exists public.plan_item_capabilities (
  kind public.plan_item_kind primary key,
  wave_min integer not null default 2 check (wave_min >= 1),
  supports_rsvp boolean not null default false,
  suggests_pois boolean not null default false,
  has_live_status boolean not null default false,
  has_check_times boolean not null default false,
  sells_tickets boolean not null default false,
  has_details_form boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.plan_item_capabilities is
  'S49: data-driven feature flags for existing plan_item_kind enum values.';

comment on column public.trip_plan_items.metadata is
  'S49: future typed plan payload. Must stay a JSON object; unknown keys are preserved.';

insert into public.plan_item_capabilities (
  kind,
  wave_min,
  supports_rsvp,
  suggests_pois,
  has_live_status,
  has_check_times,
  sells_tickets,
  has_details_form
) values
  ('lodging', 2, false, false, false, false, false, false),
  ('flight', 2, false, false, true, false, false, false),
  ('train', 2, false, false, true, false, false, false),
  ('activity', 2, true, true, false, false, false, false),
  ('other', 2, false, false, false, false, false, false)
on conflict (kind) do update set
  wave_min = excluded.wave_min,
  supports_rsvp = excluded.supports_rsvp,
  suggests_pois = excluded.suggests_pois,
  has_live_status = excluded.has_live_status,
  has_check_times = excluded.has_check_times,
  sells_tickets = excluded.sells_tickets,
  has_details_form = excluded.has_details_form,
  updated_at = now();

alter table public.plan_item_capabilities enable row level security;

drop policy if exists plan_item_capabilities_select on public.plan_item_capabilities;
create policy plan_item_capabilities_select on public.plan_item_capabilities
  for select
  to authenticated
  using (true);

revoke all on table public.plan_item_capabilities from public;
revoke all on table public.plan_item_capabilities from anon;
revoke all on table public.plan_item_capabilities from authenticated;
grant select on table public.plan_item_capabilities to authenticated;
