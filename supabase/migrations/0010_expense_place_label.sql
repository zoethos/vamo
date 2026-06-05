-- Wave 2 — OCR merchant/place label on expenses (first visible "where", pre-TripMap).
alter table expenses
  add column if not exists place_label text;
