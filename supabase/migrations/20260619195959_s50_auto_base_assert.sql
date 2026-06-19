-- S50 trust-boundary fixup (round 3):
-- For auto FX rows, clients may choose the rate snapshot but not an
-- inconsistent converted total. Manual/receipt overrides remain first-class.

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
  v_trip_base char(3);
  v_expected_base bigint;
  v_currency char(3) := upper(trim(p_currency));
  v_members uuid[];
  v_share_user uuid;
  v_share_cents bigint;
  v_share_id uuid;
  v_each bigint;
  v_remainder bigint;
  v_i int;
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

  select upper(trim(t.base_currency)) into v_trip_base
  from trips t
  where t.id = p_trip_id;

  if v_trip_base is null then
    raise exception 'trip not found';
  end if;

  if v_source = 'auto' then
    if p_fx_rate is null or p_fx_rate <= 0 then
      raise exception 'auto fx_rate must be positive';
    end if;
    v_expected_base := case
      when v_currency = v_trip_base then p_amount_cents
      else round(p_amount_cents::numeric * p_fx_rate)::bigint
    end;
    if p_base_cents <> v_expected_base then
      raise exception 'auto base_cents % must equal computed %', p_base_cents, v_expected_base;
    end if;
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
    p_id, p_trip_id, p_payer_id, p_amount_cents, v_currency, p_base_cents, p_fx_rate,
    coalesce(p_description, ''), p_category, coalesce(p_spent_at, now()), v_uid, 'committed'::expense_status,
    p_receipt_path, p_captured_lat, p_captured_lng, p_captured_at, p_place_label, p_place_id,
    v_source, p_fx_rate_manual, coalesce(p_fx_conversion_locked, false)
  );

  v_each := p_base_cents / array_length(v_members, 1);
  v_remainder := p_base_cents % array_length(v_members, 1);
  for v_i in 1..array_length(v_members, 1) loop
    v_share_user := v_members[v_i];
    v_share_cents := v_each + case when v_i <= v_remainder then 1 else 0 end;
    select (s->>'id')::uuid into v_share_id
      from jsonb_array_elements(p_shares) s
      where (s->>'user_id')::uuid = v_share_user limit 1;
    v_share_id := coalesce(v_share_id, gen_random_uuid());
    insert into expense_shares (id, expense_id, user_id, share_cents, response)
    values (v_share_id, p_id, v_share_user, v_share_cents, 'accepted'::share_response);
  end loop;

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
  v_trip_base char(3);
  v_expected_base bigint;
  v_currency char(3) := upper(trim(p_currency));
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

  select upper(trim(t.base_currency)) into v_trip_base
  from trips t
  where t.id = p_trip_id;

  if v_trip_base is null then
    raise exception 'trip not found';
  end if;

  if v_source = 'auto' then
    if p_fx_rate is null or p_fx_rate <= 0 then
      raise exception 'auto fx_rate must be positive';
    end if;
    v_expected_base := case
      when v_currency = v_trip_base then p_amount_cents
      else round(p_amount_cents::numeric * p_fx_rate)::bigint
    end;
    if p_base_cents <> v_expected_base then
      raise exception 'auto base_cents % must equal computed %', p_base_cents, v_expected_base;
    end if;
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
    p_id, p_trip_id, p_payer_id, p_amount_cents, v_currency, p_base_cents, p_fx_rate,
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
