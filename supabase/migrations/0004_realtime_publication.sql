-- Slice 9 — enable Supabase Realtime for trip-scoped tables.
-- Run after 0003_trip_capture.sql. If tables are already in the publication, ignore errors.

do $$
begin
  alter publication supabase_realtime add table public.expenses;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.settlements;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.trip_members;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.trips;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.trip_notes;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.trip_photos;
exception when duplicate_object then null;
end $$;
