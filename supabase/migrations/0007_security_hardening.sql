-- Security hardening (review findings, 2026-06-04).
-- 1) P1: drop the self-service trip_members insert policy. Both legitimate
--    membership paths are security-definer RPCs (create_trip owner insert,
--    join_trip token-validated join); the direct policy allowed any authed
--    user to self-add to any trip whose UUID they knew.
-- 2) P1: trip_balances ran with owner rights (view default), bypassing the
--    underlying tables' RLS through the API. security_invoker makes the
--    caller's RLS apply: non-members get zero rows.
-- 3) P2: settlements were "for all" to any trip member, letting any member
--    confirm/update/delete settlements they are not party to. Reads stay
--    member-wide (balances need them); writes require being a participant.
--    Finer rules (only to_user confirms; no edits after confirmed) remain
--    client-enforced for now — acceptable residual risk within a trip's
--    own membership, revisit before public launch.

-- (1) members_insert
drop policy if exists members_insert on trip_members;

-- (2) balances view respects caller RLS
alter view trip_balances set (security_invoker = on);

-- (3) settlements: read for members, writes for participants only
drop policy if exists settlements_all on settlements;

create policy settlements_read on settlements for select
  using (is_trip_member(trip_id));

create policy settlements_insert on settlements for insert
  with check (
    is_trip_member(trip_id)
    and auth.uid() in (from_user, to_user)
  );

create policy settlements_update on settlements for update
  using (auth.uid() in (from_user, to_user))
  with check (auth.uid() in (from_user, to_user));

create policy settlements_delete on settlements for delete
  using (auth.uid() in (from_user, to_user));
