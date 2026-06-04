-- Slice 8 — solo trip capture (notes + photos). Private bucket: captures.

create table if not exists trip_notes (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid not null references trips(id) on delete cascade,
  title       text not null,
  body        text not null default '',
  captured_at timestamptz not null default now(),
  created_by  uuid not null references profiles(id),
  created_at  timestamptz not null default now()
);
create index if not exists idx_trip_notes_trip on trip_notes(trip_id);

create table if not exists trip_photos (
  id            uuid primary key default gen_random_uuid(),
  trip_id       uuid not null references trips(id) on delete cascade,
  storage_path  text not null,
  caption       text,
  captured_at   timestamptz not null default now(),
  created_by    uuid not null references profiles(id),
  created_at    timestamptz not null default now()
);
create index if not exists idx_trip_photos_trip on trip_photos(trip_id);

alter table trip_notes  enable row level security;
alter table trip_photos enable row level security;

create policy trip_notes_all on trip_notes for all
  using (is_trip_member(trip_id)) with check (is_trip_member(trip_id));

create policy trip_photos_all on trip_photos for all
  using (is_trip_member(trip_id)) with check (is_trip_member(trip_id));
