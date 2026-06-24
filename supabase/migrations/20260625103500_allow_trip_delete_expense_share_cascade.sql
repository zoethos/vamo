-- Trip hard delete cascades through expenses and expense_shares. The share
-- guard blocks direct deletes unless an expense RPC is in progress, so mark
-- this owner-only RPC as an authorized internal expense cascade.
create or replace function delete_trip(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'not_authenticated';
  end if;

  select owner_id
    into v_owner_id
    from trips
   where id = p_trip_id;

  if not found then
    return;
  end if;

  if v_owner_id is distinct from auth.uid() then
    raise exception using errcode = '42501', message = 'only_owner_may_delete';
  end if;

  perform set_config('vamo.expense_rpc', '1', true);

  delete from trips where id = p_trip_id;
end;
$$;

revoke all on function delete_trip(uuid) from public;
grant execute on function delete_trip(uuid) to authenticated;
