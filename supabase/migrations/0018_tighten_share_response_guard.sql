-- S19 follow-up — integrity rule 3: block forged dispute on direct INSERT.
-- 0017 already applied on cloud; replace guard + bump parent expense on dispute (rule 4).

create or replace function expense_shares_response_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(current_setting('vamo.expense_rpc', true), '') = '1' then
      -- propose_expense may insert pending shares under the expense RPC flag.
      null;
    elsif new.response = 'pending'::share_response then
      raise exception 'pending share insert requires propose RPC';
    elsif new.response <> 'accepted'::share_response
       or new.response_reason is not null
       or new.responded_at is not null then
      raise exception 'share insert must be default consent unless propose RPC';
    end if;
  end if;
  if tg_op = 'UPDATE' then
    if new.response is distinct from old.response
       or new.response_reason is distinct from old.response_reason
       or new.responded_at is distinct from old.responded_at then
      if coalesce(current_setting('vamo.share_rpc', true), '') <> '1' then
        raise exception 'share response changes require RPC';
      end if;
    end if;
  end if;
  return new;
end;
$$;

-- Integrity rule 4: propagate share disputes via existing expenses realtime subscription.
create or replace function respond_to_share(
  p_expense_id uuid,
  p_accept boolean,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_trip_id uuid;
  v_share_id uuid;
  v_trimmed text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select e.trip_id into v_trip_id
  from expenses e
  where e.id = p_expense_id;

  if not found then
    raise exception 'expense not found';
  end if;
  if is_trip_cancelled(v_trip_id) then
    raise exception 'trip is cancelled';
  end if;
  if not exists (
    select 1 from trip_members m
    where m.trip_id = v_trip_id and m.user_id = v_uid and m.status = 'active'
  ) then
    raise exception 'not an active trip member';
  end if;

  select s.id into v_share_id
  from expense_shares s
  where s.expense_id = p_expense_id and s.user_id = v_uid;

  if not found then
    raise exception 'no share row for caller';
  end if;

  if not p_accept and v_trimmed is null then
    raise exception 'reject requires a reason';
  end if;

  perform set_config('vamo.share_rpc', '1', true);
  update expense_shares
  set
    response = case
      when p_accept then 'accepted'::share_response
      else 'rejected'::share_response
    end,
    response_reason = case when p_accept then null else v_trimmed end,
    responded_at = now()
  where id = v_share_id;

  -- Touch parent row so trip realtime (expenses subscription) refreshes peers.
  update expenses
  set spent_at = spent_at
  where id = p_expense_id;
end;
$$;

revoke all on function respond_to_share(uuid, boolean, text) from public;
grant execute on function respond_to_share(uuid, boolean, text) to authenticated;
