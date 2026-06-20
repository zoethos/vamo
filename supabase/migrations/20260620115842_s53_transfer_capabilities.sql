-- S53 Transfers: seed capabilities for the new transfer kind.
--
-- Metadata shape:
-- {
--   "subtype": "car_rental" | "train" | "transit" | "drive" | "flight",
--   "origin"?: text,
--   "destination"?: text,
--   "provider"?: text,
--   "reference"?: text
-- }
insert into public.plan_item_capabilities (
  kind,
  wave_min,
  supports_rsvp,
  suggests_pois,
  has_live_status,
  has_check_times,
  sells_tickets,
  has_details_form
)
values ('transfer', 2, false, false, true, true, false, true)
on conflict (kind) do update set
  wave_min = excluded.wave_min,
  supports_rsvp = excluded.supports_rsvp,
  suggests_pois = excluded.suggests_pois,
  has_live_status = excluded.has_live_status,
  has_check_times = excluded.has_check_times,
  sells_tickets = excluded.sells_tickets,
  has_details_form = excluded.has_details_form,
  updated_at = now();
