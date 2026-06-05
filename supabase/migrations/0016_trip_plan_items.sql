-- S18 / R4 — TripBoard plan items + shared checklists
-- S21 extends trip_plan_items (kind=activity) — no separate events table.

do $$ begin
  create type plan_item_kind as enum (
    'lodging', 'flight', 'train', 'activity', 'other'
  );
exception when duplicate_object then null; end $$;

create table if not exists trip_plan_items (
  id              uuid primary key default gen_random_uuid(),
  trip_id         uuid not null references trips(id) on delete cascade,
  kind            plan_item_kind not null default 'other',
  title           text not null,
  notes           text,
  starts_at       timestamptz,
  ends_at         timestamptz,
  external_ref    text,
  attachment_path text,
  position        int not null default 0,
  created_by      uuid not null references profiles(id),
  updated_by      uuid references profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists idx_trip_plan_items_trip on trip_plan_items(trip_id, position);

create table if not exists trip_list_items (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid not null references trips(id) on delete cascade,
  list_name   text not null,
  label       text not null,
  checked_by  uuid references profiles(id),
  checked_at  timestamptz,
  position    int not null default 0,
  created_by  uuid not null references profiles(id),
  created_at  timestamptz not null default now()
);

create index if not exists idx_trip_list_items_trip on trip_list_items(trip_id, list_name, position);

alter table trip_plan_items enable row level security;
alter table trip_list_items enable row level security;

-- ---------- updated_by trigger (plan items only) ----------
create or replace function trip_plan_items_set_updated_by() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_by = auth.uid();
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trip_plan_items_updated_by_trg on trip_plan_items;
create trigger trip_plan_items_updated_by_trg
  before update on trip_plan_items
  for each row execute function trip_plan_items_set_updated_by();

-- ---------- trip_plan_items RLS (S17 writable pattern + restrictive DELETE) ----------
create policy trip_plan_items_select on trip_plan_items
  for select using (is_trip_member(trip_id));

create policy trip_plan_items_insert on trip_plan_items
  for insert with check (
    is_trip_member(trip_id) and is_trip_writable(trip_id)
  );

create policy trip_plan_items_update on trip_plan_items
  for update
  using (is_trip_member(trip_id))
  with check (is_trip_member(trip_id) and is_trip_writable(trip_id));

create policy trip_plan_items_delete on trip_plan_items
  for delete using (is_trip_member(trip_id));

create policy trip_plan_items_block_delete_closed on trip_plan_items
  as restrictive for delete using (is_trip_writable(trip_id));

-- ---------- trip_list_items RLS ----------
create policy trip_list_items_select on trip_list_items
  for select using (is_trip_member(trip_id));

create policy trip_list_items_insert on trip_list_items
  for insert with check (
    is_trip_member(trip_id) and is_trip_writable(trip_id)
  );

create policy trip_list_items_update on trip_list_items
  for update
  using (is_trip_member(trip_id))
  with check (is_trip_member(trip_id) and is_trip_writable(trip_id));

create policy trip_list_items_delete on trip_list_items
  for delete using (is_trip_member(trip_id));

create policy trip_list_items_block_delete_closed on trip_list_items
  as restrictive for delete using (is_trip_writable(trip_id));

-- Realtime (same pattern as expenses)
do $$ begin
  alter publication supabase_realtime add table public.trip_plan_items;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.trip_list_items;
exception when duplicate_object then null;
end $$;
