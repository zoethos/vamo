-- S21 merge gate — FK cascade deletes must not hit the RSVP GUC guard.
-- 0023 is already on cloud; do not edit it.
--
-- Direct member DELETE stays constrained by restrictive RLS (own-row +
-- is_trip_writable). Withdraw goes through clear_event_rsvp for analytics.
-- Plan-item and trip deletes cascade rsvp rows without the RPC flag.

create or replace function trip_plan_item_rsvps_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('vamo.rsvp_rpc', true), '') <> '1' then
    raise exception 'rsvp changes require RPC';
  end if;
  return new;
end;
$$;

drop trigger if exists trip_plan_item_rsvps_guard_trg on trip_plan_item_rsvps;
create trigger trip_plan_item_rsvps_guard_trg
  before insert or update on trip_plan_item_rsvps
  for each row execute function trip_plan_item_rsvps_guard();
