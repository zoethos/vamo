-- S20 / R6 — trip budget (D3) + constant FX table (D4)
-- Contract: docs/design/MONEY_GOVERNANCE.md D3, D4, A3

create extension if not exists http with schema extensions;

do $$ begin
  create type budget_mode as enum ('none', 'informational', 'formal');
exception when duplicate_object then null; end $$;

alter table trips
  add column if not exists budget_mode budget_mode not null default 'none',
  add column if not exists budget_cents bigint;

-- ---------- trip_fx_rates (D4 constant-rate table) ----------
create table if not exists trip_fx_rates (
  id           uuid primary key default gen_random_uuid(),
  trip_id      uuid not null references trips(id) on delete cascade,
  currency     char(3) not null,
  rate         numeric not null check (rate > 0),
  source       text not null,
  captured_at  timestamptz not null default now(),
  captured_by  uuid not null references profiles(id),
  unique (trip_id, currency)
);

create index if not exists idx_trip_fx_rates_trip on trip_fx_rates(trip_id);

-- ---------- column guards (RPC-only budget / FX writes) ----------
create or replace function trips_budget_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.budget_mode is distinct from old.budget_mode
       or new.budget_cents is distinct from old.budget_cents then
      if coalesce(current_setting('vamo.budget_rpc', true), '') <> '1' then
        raise exception 'budget changes require RPC';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trips_budget_guard_trg on trips;
create trigger trips_budget_guard_trg
  before update on trips
  for each row execute function trips_budget_guard();

create or replace function trip_fx_rates_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('vamo.fx_rpc', true), '') <> '1' then
    raise exception 'trip_fx_rates changes require RPC';
  end if;
  return new;
end;
$$;

drop trigger if exists trip_fx_rates_guard_trg on trip_fx_rates;
create trigger trip_fx_rates_guard_trg
  before insert or update on trip_fx_rates
  for each row execute function trip_fx_rates_guard();

-- ---------- RLS ----------
alter table trip_fx_rates enable row level security;

drop policy if exists trip_fx_rates_read on trip_fx_rates;
create policy trip_fx_rates_read on trip_fx_rates for select
  using (is_trip_member(trip_id));

drop policy if exists trip_fx_rates_write on trip_fx_rates;
create policy trip_fx_rates_write on trip_fx_rates for insert
  with check (
    is_trip_member(trip_id)
    and can_edit_trip_content(trip_id)
    and is_trip_writable(trip_id)
  );

drop policy if exists trip_fx_rates_update on trip_fx_rates;
create policy trip_fx_rates_update on trip_fx_rates for update
  using (
    is_trip_member(trip_id)
    and can_edit_trip_content(trip_id)
    and is_trip_writable(trip_id)
  )
  with check (
    is_trip_member(trip_id)
    and can_edit_trip_content(trip_id)
    and is_trip_writable(trip_id)
  );

drop policy if exists trip_fx_rates_block_delete_closed on trip_fx_rates;
create policy trip_fx_rates_block_delete_closed on trip_fx_rates
  as restrictive for delete
  using (is_trip_writable(trip_id));

-- ---------- private market fetch (never granted to authenticated) ----------
create or replace function _fetch_market_fx_rate(
  p_trip_base char(3),
  p_currency char(3)
) returns table(out_rate numeric, out_source text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_key text;
  v_url text;
  v_resp extensions.http_response;
  v_body jsonb;
  v_pivot_rates jsonb;
  v_trip_pivot numeric;
  v_currency_pivot numeric;
  v_rebased_units numeric;
  v_trip_base_upper char(3);
  v_currency_upper char(3);
begin
  v_trip_base_upper := upper(trim(p_trip_base));
  v_currency_upper := upper(trim(p_currency));

  if v_currency_upper = v_trip_base_upper then
    out_rate := 1;
    out_source := 'identity';
    return next;
    return;
  end if;

  v_key := coalesce(
    nullif(current_setting('app.exchangerate_access_key', true), ''),
    (select decrypted_secret from vault.decrypted_secrets
     where name = 'exchangerate_access_key' limit 1)
  );
  if v_key is null or v_key = '' then
    raise exception 'EXCHANGERATE_ACCESS_KEY not configured';
  end if;

  v_url := 'https://api.exchangerate.host/latest?access_key='
    || v_key || '&base=EUR';
  v_resp := extensions.http_get(v_url);
  if v_resp.status <> 200 then
    raise exception 'fx upstream failed: %', v_resp.status;
  end if;

  v_body := v_resp.content::jsonb;
  if coalesce((v_body->>'success')::boolean, true) = false then
    raise exception 'fx upstream error';
  end if;

  v_pivot_rates := v_body->'rates';
  if v_pivot_rates is null then
    raise exception 'fx upstream invalid';
  end if;

  v_trip_pivot := case
    when v_trip_base_upper = 'EUR' then 1
    else (v_pivot_rates->>v_trip_base_upper)::numeric
  end;
  if v_trip_pivot is null or v_trip_pivot <= 0 then
    raise exception 'unknown trip base currency %', v_trip_base_upper;
  end if;

  if v_currency_upper <> 'EUR' and not (v_pivot_rates ? v_currency_upper) then
    raise exception 'unknown currency %', v_currency_upper;
  end if;

  v_currency_pivot := case
    when v_currency_upper = 'EUR' then 1
    else (v_pivot_rates->>v_currency_upper)::numeric
  end;
  if v_currency_pivot is null or v_currency_pivot <= 0 then
    raise exception 'invalid rate for %', v_currency_upper;
  end if;

  v_rebased_units := v_currency_pivot / v_trip_pivot;
  out_rate := 1.0 / v_rebased_units;
  out_source := 'exchangerate.host';
  return next;
end;
$$;

revoke all on function _fetch_market_fx_rate(char(3), char(3)) from public;

-- Private writer accepting rate — service_role / internal RPC only.
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

  return v_id;
end;
$$;

revoke all on function _apply_trip_fx_rate(uuid, char(3), numeric, text, uuid) from public;

-- ---------- public RPCs (client sends trip + currency/mode only) ----------
create or replace function set_trip_budget(
  p_trip_id uuid,
  p_mode budget_mode,
  p_cents bigint default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not can_edit_trip_content(p_trip_id) then
    raise exception 'only owner or co-admin may set budget';
  end if;
  if not is_trip_writable(p_trip_id) then
    raise exception 'trip is read-only';
  end if;
  if p_mode = 'formal'::budget_mode and (p_cents is null or p_cents <= 0) then
    raise exception 'formal budget requires a positive amount';
  end if;
  if p_mode = 'none'::budget_mode then
    p_cents := null;
  elsif p_mode = 'informational'::budget_mode and p_cents is not null and p_cents <= 0 then
    raise exception 'budget amount must be positive when set';
  end if;

  perform set_config('vamo.budget_rpc', '1', true);
  update trips
  set budget_mode = p_mode,
      budget_cents = case when p_mode = 'none'::budget_mode then null else p_cents end
  where id = p_trip_id;
end;
$$;

create or replace function capture_trip_fx_rate(
  p_trip_id uuid,
  p_currency char(3)
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_base char(3);
  v_rate numeric;
  v_source text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not can_edit_trip_content(p_trip_id) then
    raise exception 'only owner or co-admin may capture FX rates';
  end if;
  if not is_trip_writable(p_trip_id) then
    raise exception 'trip is read-only';
  end if;

  select base_currency into v_base from trips where id = p_trip_id;
  if not found then
    raise exception 'trip not found';
  end if;

  select f.out_rate, f.out_source
  into v_rate, v_source
  from _fetch_market_fx_rate(v_base, p_currency) f;

  return _apply_trip_fx_rate(
    p_trip_id,
    p_currency,
    v_rate,
    v_source,
    v_uid
  );
end;
$$;

revoke all on function set_trip_budget(uuid, budget_mode, bigint) from public;
grant execute on function set_trip_budget(uuid, budget_mode, bigint) to authenticated;

revoke all on function capture_trip_fx_rate(uuid, char(3)) from public;
grant execute on function capture_trip_fx_rate(uuid, char(3)) to authenticated;

-- Burn-down helper: committed spend only (S19 invariant).
create or replace function trip_committed_spend_cents(p_trip_id uuid)
returns bigint
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not is_trip_member(p_trip_id) then
    raise exception 'not a trip member';
  end if;

  return (
    select coalesce(sum(base_cents), 0)::bigint
    from expenses
    where trip_id = p_trip_id
      and status = 'committed'::expense_status
  );
end;
$$;

revoke all on function trip_committed_spend_cents(uuid) from public;
grant execute on function trip_committed_spend_cents(uuid) to authenticated;
