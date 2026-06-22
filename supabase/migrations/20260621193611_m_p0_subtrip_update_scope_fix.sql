-- M-P0 follow-up: require regular members to already own the old plan-item
-- scope before updating it. Without this, a subtrip member could move a
-- main-lane item into their subtrip and then edit it.
drop policy if exists trip_plan_items_update on public.trip_plan_items;

create policy trip_plan_items_update on public.trip_plan_items
  for update
  using (
    public.is_trip_member(trip_id)
    and public.can_edit_plan_item_scope(trip_id, subtrip_id)
  )
  with check (
    public.is_trip_member(trip_id)
    and public.is_trip_writable(trip_id)
    and public.can_edit_plan_item_scope(trip_id, subtrip_id)
  );
