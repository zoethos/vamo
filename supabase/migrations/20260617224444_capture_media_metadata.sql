-- Capture media metadata at ingest (TripMap groundwork).
--
-- trip_photos.captured_at remains the Vamo add/import timestamp.
-- media_captured_at is the original photo timestamp from EXIF when available.
-- Location metadata is nullable and only populated by the app after the user
-- opts in to capture location tagging.
alter table public.trip_photos
  add column if not exists captured_lat double precision,
  add column if not exists captured_lng double precision,
  add column if not exists media_captured_at timestamptz;
