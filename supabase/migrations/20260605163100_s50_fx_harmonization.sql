-- S50 — per-expense FX control + harmonization on refresh.
-- Entry-time snapshot: expenses.fx_rate / base_cents captured at propose/commit;
-- manual/receipt overrides lock out automatic refresh. Remainder rule matches
-- client equalSplit: sorted active member user_ids, first v_remainder shares +1¢.

-- ---------- columns ----------
alter table expenses
  add column if not exists fx_rate_source text not null default 'auto'
    check (fx_rate_source in ('auto', 'receipt', 'manual')),
  add column if not exists fx_rate_manual numeric,
  add column if not exists fx_conversion_locked boolean not null default false;

comment on column expenses.fx_rate_source is
  'How fx_rate/base_cents were chosen: auto (trip table), receipt (printed total), manual (editor override).';
comment on column expenses.fx_rate_manual is
  'Optional explicit rate when fx_rate_source = receipt (base units per 1 expense currency).';
comment on column expenses.fx_conversion_locked is
  'When true, FX refresh must not change base_cents/fx_rate/shares for this expense.';

-- ---------- guards (RPC-only FX field writes) ----------
create or replace function expenses_fx_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
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
  if tg_op = 'INSERT' then
    if new.fx_rate_source <> 'auto'
       or new.fx_rate_manual is not null
       or new.fx_conversion_locked then
      if coalesce(current_setting('vamo.expense_rpc', true), '') <> '1'
         and coalesce(current_setting('vamo.fx_amend_rpc', true), '') <> '1' then
        raise exception 'non-default expense FX fields require RPC';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists expenses_fx_guard_trg on expenses;
create trigger expenses_fx_guard_trg
  before insert or update on expenses
  for each row execute function expenses_fx_guard();

create or replace function expense_shares_cents_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.share_cents is distinct from old.share_cents then
    if coalesce(current_setting('vamo.expense_rpc', true), '') <> '1'
       and coalesce(current_setting('vamo.fx_amend_rpc', true), '') <> '1'
       and coalesce(current_setting('vamo.fx_refresh_rpc', true), '') <> '1' then
      raise exception 'share_cents changes require RPC';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists expense_shares_cents_guard_trg on expense_shares;
create trigger expense_shares_cents_guard_trg
  before insert or update on expense_shares
  for each row execute function expense_shares_cents_guard();

-- ---------- helpers ----------
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

  if v_sum <> p_base_cents then
    raise exception 'share sum % != base_cents %', v_sum, p_base_cents;
  end if;
end;
$$;

revoke all on function _resplit_expense_shares(uuid, bigint) from public;

create or replace function _refresh_auto_expense_conversions(
  p_trip_id uuid,
  p_currency char(3),
  p_rate numeric
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_expense record;
  v_base bigint;
begin
  perform set_config('vamo.fx_refresh_rpc', '1', true);

  for v_expense in
    select e.id, e.amount_cents
    from expenses e
    where e.trip_id = p_trip_id
      and upper(trim(e.currency)) = upper(trim(p_currency))
      and e.fx_rate_source = 'auto'
      and not e.fx_conversion_locked
      and e.status <> 'cancelled'::expense_status
  loop
    v_base := round(v_expense.amount_cents * p_rate)::bigint;
    if v_base <= 0 then
      continue;
    end if;
    update expenses
    set base_cents = v_base,
        fx_rate = p_rate
    where id = v_expense.id;
    perform _resplit_expense_shares(v_expense.id, v_base);
  end loop;
end;
$$;

revoke all on function _refresh_auto_expense_conversions(uuid, char(3), numeric) from public;

-- Hook refresh into the private trip-rate writer (service smoke + capture).
create or replace function _apply_trip_fx_rate(
  p_trip_id uuid,
  p_currency char(3),
  p_rate numeric,
  p_source text,
  p_captured_by uuid
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  perform set_config('vamo.fx_rpc', '1', true);

  insert into trip_fx_rates (
    trip_id, currency, rate, source, captured_by, captured_at
  ) values (
    p_trip_id,
    upper(trim(p_currency)),
    p_rate,
    p_source,
    p_captured_by,
    now()
  )
  on conflict (trip_id, currency) do update
  set rate = excluded.rate,
      source = excluded.source,
      captured_by = excluded.captured_by,
      captured_at = excluded.captured_at
  returning id into v_id;

  perform _refresh_auto_expense_conversions(p_trip_id, p_currency, p_rate);

  return v_id;
end;
$$;

revoke all on function _apply_trip_fx_rate(uuid, char(3), numeric, text, uuid) from public;
grant execute on function _apply_trip_fx_rate(uuid, char(3), numeric, text, uuid) to service_role;

-- ---------- amend RPC (trip editor only) ----------
create or replace function amend_expense_conversion(
  p_expense_id uuid,
  p_base_cents bigint,
  p_fx_rate numeric default null,
  p_fx_rate_source text default 'manual',
  p_fx_rate_manual numeric default null,
  p_lock boolean default true
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_trip_id uuid;
  v_amount bigint;
  v_fx numeric;
  v_source text := lower(trim(p_fx_rate_source));
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if v_source not in ('auto', 'receipt', 'manual') then
    raise exception 'invalid fx_rate_source';
  end if;

  select trip_id, amount_cents
  into v_trip_id, v_amount
  from expenses
  where id = p_expense_id;

  if not found then
    raise exception 'expense not found';
  end if;

  if not can_edit_trip_content(v_trip_id) then
    raise exception 'only owner or co-admin may amend conversion';
  end if;
  if not is_trip_writable(v_trip_id) then
    raise exception 'trip is read-only';
  end if;
  if p_base_cents <= 0 or v_amount <= 0 then
    raise exception 'amount must be positive';
  end if;

  v_fx := coalesce(p_fx_rate, p_base_cents::numeric / v_amount::numeric);

  perform set_config('vamo.fx_amend_rpc', '1', true);

  update expenses
  set base_cents = p_base_cents,
      fx_rate = v_fx,
      fx_rate_source = v_source,
      fx_rate_manual = p_fx_rate_manual,
      fx_conversion_locked = coalesce(p_lock, true)
  where id = p_expense_id;

  perform _resplit_expense_shares(p_expense_id, p_base_cents);
end;
$$;

revoke all on function amend_expense_conversion(uuid, bigint, numeric, text, numeric, boolean) from public;
grant execute on function amend_expense_conversion(uuid, bigint, numeric, text, numeric, boolean) to authenticated;
