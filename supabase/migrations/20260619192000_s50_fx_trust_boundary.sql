-- S50 trust-boundary fixups: block forged direct INSERTs, prune stale shares on
-- re-split, and route committed expense sync through insert_committed_expense.

-- ---------- tighten guards ----------
create or replace function expenses_fx_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(current_setting('vamo.expense_rpc', true), '') <> '1' then
      raise exception 'expense insert requires RPC';
    end if;
  elsif tg_op = 'UPDATE' then
    if new.base_cents is distinct from old.base_cents
       or new.fx_rate is distinct from old.fx_rate
       or new.fx_rate_source is distinct from old.fx_rate_source
       or new.fx_rate_manual is distinct from old.fx_rate_manual
       or new.fx_conversion_locked is distinct from old.fx_conversion_locked then
      if coalesce(current_setting('vamo.expense_rpc', true), '') <> '1'
         and coalesce(current_setting('vamo.fx_amend_rpc', true), '') <> '1'
         and coalesce(current_setting('vamo.fx_refresh_rpc', true), '') <> '1' then
        raise exception 'expense FX fields require RPC';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create or replace function expense_shares_cents_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT'
     or (tg_op = 'UPDATE' and new.share_cents is distinct from old.share_cents) then
    if coalesce(current_setting('vamo.expense_rpc', true), '') <> '1'
       and coalesce(current_setting('vamo.fx_amend_rpc', true), '') <> '1'
       and coalesce(current_setting('vamo.fx_refresh_rpc', true), '') <> '1' then
      raise exception 'share_cents changes require RPC';
    end if;
  end if;
  return new;
end;
$$;

create or replace function expense_shares_delete_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('vamo.expense_rpc', true), '') <> '1'
     and coalesce(current_setting('vamo.fx_amend_rpc', true), '') <> '1'
     and coalesce(current_setting('vamo.fx_refresh_rpc', true), '') <> '1' then
    raise exception 'share delete requires RPC';
  end if;
  return new;
end;
$$;

drop trigger if exists expense_shares_delete_guard_trg on expense_shares;
create trigger expense_shares_delete_guard_trg
  before delete on expense_shares
  for each row execute function expense_shares_delete_guard();

-- ---------- re-split: drop shares for inactive/non-member users ----------
create or replace function _resplit_expense_shares(
  p_expense_id uuid,
  p_base_cents bigint
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_trip_id uuid;
  v_members uuid[];
  v_count int;
  v_each bigint;
  v_remainder bigint;
  v_i int;
  v_share bigint;
  v_sum bigint := 0;
  v_uid uuid;
begin
  select trip_id into v_trip_id from expenses where id = p_expense_id;
  if not found then
    raise exception 'expense not found';
  end if;

  select array_agg(m.user_id order by m.user_id)
  into v_members
  from trip_members m
  where m.trip_id = v_trip_id and m.status = 'active';

  v_count := coalesce(array_length(v_members, 1), 0);
  if v_count = 0 then
    raise exception 'trip has no active members';
  end if;

  v_each := p_base_cents / v_count;
  v_remainder := p_base_cents % v_count;

  for v_i in 1..v_count loop
    v_uid := v_members[v_i];
    v_share := v_each + case when v_i <= v_remainder then 1 else 0 end;
    v_sum := v_sum + v_share;
    update expense_shares
    set share_cents = v_share
    where expense_id = p_expense_id and user_id = v_uid;
    if not found then
      insert into expense_shares (id, expense_id, user_id, share_cents, response)
      values (gen_random_uuid(), p_expense_id, v_uid, v_share, 'accepted'::share_response);
    end if;
  end loop;

  delete from expense_shares
  where expense_id = p_expense_id
    and not (user_id = any(v_members));

  if v_sum <> p_base_cents then
    raise exception 'share sum % != base_cents %', v_sum, p_base_cents;
  end if;
end;
$$;

revoke all on function _resplit_expense_shares(uuid, bigint) from public;

-- ---------- committed expense sync RPC (offline outbox path) ----------
create or replace function insert_committed_expense(
  p_id uuid,
  p_trip_id uuid,
  p_payer_id uuid,
  p_amount_cents bigint,
  p_currency char(3),
  p_base_cents bigint,
  p_fx_rate numeric,
  p_description text,
  p_category text default null,
  p_spent_at timestamptz default null,
  p_receipt_path text default null,
  p_captured_lat double precision default null,
  p_captured_lng double precision default null,
  p_captured_at timestamptz default null,
  p_place_label text default null,
  p_place_id uuid default null,
  p_fx_rate_source text default 'auto',
  p_fx_rate_manual numeric default null,
  p_fx_conversion_locked boolean default false,
  p_shares jsonb default '[]'::jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_source text := lower(trim(p_fx_rate_source));
  v_members uuid[];
  v_share jsonb;
  v_share_user uuid;
  v_share_cents bigint;
  v_share_id uuid;
  v_sum bigint := 0;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not is_trip_member(p_trip_id) then
    raise exception 'not a trip member';
  end if;
  if not is_trip_writable(p_trip_id) then
    raise exception 'trip is read-only';
  end if;
  if p_amount_cents <= 0 or p_base_cents <= 0 then
    raise exception 'amount must be positive';
  end if;
  if v_source not in ('auto', 'receipt', 'manual') then
    raise exception 'invalid fx_rate_source';
  end if;

  select array_agg(m.user_id order by m.user_id)
  into v_members
  from trip_members m
  where m.trip_id = p_trip_id and m.status = 'active';

  if v_members is null or not (p_payer_id = any(v_members)) then
    raise exception 'payer must be an active member';
  end if;

  perform set_config('vamo.expense_rpc', '1', true);

  insert into expenses (
    id, trip_id, payer_id, amount_cents, currency, base_cents, fx_rate,
    description, category, spent_at, created_by, status,
    receipt_path, captured_lat, captured_lng, captured_at, place_label, place_id,
    fx_rate_source, fx_rate_manual, fx_conversion_locked
  ) values (
    p_id, p_trip_id, p_payer_id, p_amount_cents, upper(trim(p_currency)), p_base_cents, p_fx_rate,
    coalesce(p_description, ''), p_category, coalesce(p_spent_at, now()), v_uid, 'committed'::expense_status,
    p_receipt_path, p_captured_lat, p_captured_lng, p_captured_at, p_place_label, p_place_id,
    v_source, p_fx_rate_manual, coalesce(p_fx_conversion_locked, false)
  );

  for v_share in select * from jsonb_array_elements(p_shares) loop
    v_share_id := (v_share->>'id')::uuid;
    v_share_user := (v_share->>'user_id')::uuid;
    v_share_cents := (v_share->>'share_cents')::bigint;
    if v_share_id is null or v_share_user is null or v_share_cents is null then
      raise exception 'invalid share payload';
    end if;
    if not (v_share_user = any(v_members)) then
      raise exception 'share user must be an active member';
    end if;
    v_sum := v_sum + v_share_cents;
    insert into expense_shares (id, expense_id, user_id, share_cents, response)
    values (v_share_id, p_id, v_share_user, v_share_cents, 'accepted'::share_response);
  end loop;

  if v_sum <> p_base_cents then
    raise exception 'sum(shares)=% must equal base_cents=%', v_sum, p_base_cents;
  end if;

  return p_id;
end;
$$;

revoke all on function insert_committed_expense(
  uuid, uuid, uuid, bigint, char(3), bigint, numeric, text, text, timestamptz,
  text, double precision, double precision, timestamptz, text, uuid, text,
  numeric, boolean, jsonb
) from public;
grant execute on function insert_committed_expense(
  uuid, uuid, uuid, bigint, char(3), bigint, numeric, text, text, timestamptz,
  text, double precision, double precision, timestamptz, text, uuid, text,
  numeric, boolean, jsonb
) to authenticated;

-- ---------- propose_expense: accept FX metadata on insert (no follow-up amend) ----------
create or replace function propose_expense(
  p_id uuid,
  p_trip_id uuid,
  p_payer_id uuid,
  p_amount_cents bigint,
  p_currency char(3),
  p_base_cents bigint,
  p_fx_rate numeric,
  p_description text,
  p_category text default null,
  p_spent_at timestamptz default now(),
  p_fx_rate_source text default 'auto',
  p_fx_rate_manual numeric default null,
  p_fx_conversion_locked boolean default false
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_members uuid[];
  v_count int;
  v_each bigint;
  v_remainder bigint;
  v_share bigint;
  v_i int;
  v_share_id uuid;
  v_sum bigint := 0;
  v_source text := lower(trim(p_fx_rate_source));
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not can_edit_trip_content(p_trip_id) then
    raise exception 'only owner or co-admin may propose expenses';
  end if;
  if not is_trip_writable(p_trip_id) then
    raise exception 'trip is read-only';
  end if;
  if p_amount_cents <= 0 or p_base_cents <= 0 then
    raise exception 'amount must be positive';
  end if;
  if v_source not in ('auto', 'receipt', 'manual') then
    raise exception 'invalid fx_rate_source';
  end if;

  select array_agg(m.user_id order by m.user_id)
  into v_members
  from trip_members m
  where m.trip_id = p_trip_id and m.status = 'active';

  v_count := coalesce(array_length(v_members, 1), 0);
  if v_count = 0 then
    raise exception 'trip has no active members';
  end if;

  if not (p_payer_id = any(v_members)) then
    raise exception 'payer must be an active member';
  end if;

  perform set_config('vamo.expense_rpc', '1', true);

  insert into expenses (
    id, trip_id, payer_id, amount_cents, currency, base_cents, fx_rate,
    description, category, spent_at, created_by, status,
    fx_rate_source, fx_rate_manual, fx_conversion_locked
  ) values (
    p_id, p_trip_id, p_payer_id, p_amount_cents, p_currency, p_base_cents, p_fx_rate,
    coalesce(p_description, ''), p_category, coalesce(p_spent_at, now()), v_uid,
    'proposed'::expense_status,
    v_source, p_fx_rate_manual, coalesce(p_fx_conversion_locked, false)
  );

  v_each := p_base_cents / v_count;
  v_remainder := p_base_cents % v_count;

  for v_i in 1..v_count loop
    v_share_id := gen_random_uuid();
    v_share := v_each + case when v_i <= v_remainder then 1 else 0 end;
    v_sum := v_sum + v_share;
    insert into expense_shares (id, expense_id, user_id, share_cents, response)
    values (v_share_id, p_id, v_members[v_i], v_share, 'pending'::share_response);
  end loop;

  if v_sum <> p_base_cents then
    raise exception 'share invariant violated';
  end if;

  return p_id;
end;
$$;

revoke all on function propose_expense(
  uuid, uuid, uuid, bigint, char(3), bigint, numeric, text, text, timestamptz,
  text, numeric, boolean
) from public;
grant execute on function propose_expense(
  uuid, uuid, uuid, bigint, char(3), bigint, numeric, text, text, timestamptz,
  text, numeric, boolean
) to authenticated;
