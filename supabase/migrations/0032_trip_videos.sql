-- S30 — video capture, stored in the existing private captures bucket.

create table if not exists public.trip_videos (
  id uuid primary key default extensions.gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  storage_path text not null,
  caption text,
  captured_at timestamptz not null default now(),
  captured_lat double precision,
  captured_lng double precision,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_trip_videos_trip
  on public.trip_videos(trip_id);

alter table public.trip_videos enable row level security;

drop policy if exists trip_videos_all on public.trip_videos;
create policy trip_videos_all on public.trip_videos
  for all to authenticated
  using (public.is_trip_member(trip_id))
  with check (
    public.is_trip_member(trip_id)
    and public.is_trip_writable(trip_id)
  );

drop policy if exists trip_videos_block_delete_closed on public.trip_videos;
create policy trip_videos_block_delete_closed on public.trip_videos
  as restrictive for delete to authenticated
  using (public.is_trip_writable(trip_id));

do $$ begin
  alter publication supabase_realtime add table public.trip_videos;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
