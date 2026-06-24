-- Owner-only hard delete for trips accidentally created from the list UI.
create or replace function delete_trip(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not is_trip_owner(p_trip_id) then
    raise exception 'only owner may delete';
  end if;

  delete from trips where id = p_trip_id;
end;
$$;

revoke all on function delete_trip(uuid) from public;
grant execute on function delete_trip(uuid) to authenticated;
