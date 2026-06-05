-- Slice 14 — optional receipt photo + capture metadata on expenses.
alter table expenses
  add column if not exists receipt_path text,
  add column if not exists captured_lat double precision,
  add column if not exists captured_lng double precision,
  add column if not exists captured_at timestamptz;
