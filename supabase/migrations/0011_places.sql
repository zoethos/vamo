-- Wave 2 — resolved places from receipt OCR + EXIF cross-check.
create table if not exists places (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid not null references trips(id) on delete cascade,
  label       text not null,
  address     text,
  lat         double precision,
  lng         double precision,
  source      text not null check (source in ('exif', 'receipt', 'both')),
  confidence  real not null default 0.5,
  created_by  uuid not null references profiles(id),
  created_at  timestamptz not null default now()
);

create index if not exists idx_places_trip on places(trip_id);

alter table expenses
  add column if not exists place_id uuid references places(id);

alter table places enable row level security;

create policy places_all on places for all
  using (is_trip_member(trip_id))
  with check (is_trip_member(trip_id));
