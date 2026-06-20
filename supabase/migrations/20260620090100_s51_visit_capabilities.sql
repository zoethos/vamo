-- S51 — capability row + metadata contract for the 'visit' plan-item kind.
-- Separate from the ALTER TYPE migration so 'visit' is committed/usable here.
--
-- Visit metadata shape (trip_plan_items.metadata stays a JSON object per the
-- S49 jsonb_typeof = 'object' check):
--   { "place_label": text, "address"?: text, "lat"?: number, "lng"?: number,
--     "place_id"?: uuid (references places.id) }
-- suggests_pois drives the in-app "add from this trip's places" surfacing; the
-- external POI-discovery provider (P1) reads the same flag with no schema churn.

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
  ('visit', 2, false, true, false, false, false, true)
on conflict (kind) do update set
  wave_min = excluded.wave_min,
  supports_rsvp = excluded.supports_rsvp,
  suggests_pois = excluded.suggests_pois,
  has_live_status = excluded.has_live_status,
  has_check_times = excluded.has_check_times,
  sells_tickets = excluded.sells_tickets,
  has_details_form = excluded.has_details_form,
  updated_at = now();
