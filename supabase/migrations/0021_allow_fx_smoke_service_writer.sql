-- Allow only the service-role smoke harness to use the private FX writer.
--
-- This keeps client users on capture_trip_fx_rate(), while letting smoke test
-- refresh/forward-only invariants without making repeated live provider calls.

grant execute on function _apply_trip_fx_rate(uuid, char(3), numeric, text, uuid) to service_role;
