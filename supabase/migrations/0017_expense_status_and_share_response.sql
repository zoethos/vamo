-- S19 / R5 — expense status machine + share consent responses
-- Contract: docs/workflows/expense-consent.md · INVARIANT 1: balances filter on expense status only.

do $$ begin
  create type expense_status as enum ('proposed', 'committed', 'cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type share_response as enum ('pending', 'accepted', 'rejected');
exception when duplicate_object then null; end $$;

alter table expenses
  add column if not exists status expense_status not null default 'committed';

alter table expense_shares
  add column if not exists response share_response not null default 'accepted',
  add column if not exists response_reason text,
  add column if not exists responded_at timestamptz;

-- ---------- trip_balances (INVARIANT 1: committed expenses only) ----------
create or replace view trip_balances as
with paid as (
  select trip_id, payer_id as user_id, sum(base_cents) as paid_cents
  from expenses
  where status = 'committed'::expense_status
  group by trip_id, payer_id
),
owed as (
  select e.trip_id, s.user_id, sum(s.share_cents) as owed_cents
  from expense_shares s
  join expenses e on e.id = s.expense_id
  where e.status = 'committed'::expense_status
  group by e.trip_id, s.user_id
),
settled_out as (
  select trip_id, from_user as user_id, sum(amount_cents) as paid_cents
  from settlements
  group by trip_id, from_user
),
settled_in as (
  select trip_id, to_user as user_id, sum(amount_cents) as got_cents
  from settlements
  group by trip_id, to_user
)
select
  m.trip_id,
  m.user_id,
  coalesce(p.paid_cents, 0) - coalesce(o.owed_cents, 0)
    + coalesce(so.paid_cents, 0) - coalesce(si.got_cents, 0) as net_cents
from trip_members m
left join paid p on p.trip_id = m.trip_id and p.user_id = m.user_id
left join owed o on o.trip_id = m.trip_id and o.user_id = m.user_id
left join settled_out so on so.trip_id = m.trip_id and so.user_id = m.user_id
left join settled_in si on si.trip_id = m.trip_id and si.user_id = m.user_id
where m.status = 'active';

alter view trip_balances set (security_invoker = on);

-- ---------- column guards (RPC-only status / response writes) ----------
create or replace function expenses_status_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.status <> 'committed'::expense_status then
    if coalesce(current_setting('vamo.expense_rpc', true), '') <> '1' then
      raise exception 'non-committed expense insert requires RPC';
    end if;
  end if;
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if coalesce(current_setting('vamo.expense_rpc', true), '') <> '1' then
      raise exception 'expense status changes require RPC';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists expenses_status_guard_trg on expenses;
create trigger expenses_status_guard_trg
  before insert or update on expenses
  for each row execute function expenses_status_guard();

create or replace function expense_shares_response_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.response = 'pending'::share_response then
    if coalesce(current_setting('vamo.expense_rpc', true), '') <> '1' then
      raise exception 'pending share insert requires propose RPC';
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

drop trigger if exists expense_shares_response_guard_trg on expense_shares;
create trigger expense_shares_response_guard_trg
  before insert or update on expense_shares
  for each row execute function expense_shares_response_guard();

-- ---------- RPCs ----------
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
  p_spent_at timestamptz default now()
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_member record;
  v_members uuid[];
  v_count int;
  v_each bigint;
  v_remainder bigint;
  v_share bigint;
  v_i int;
  v_share_id uuid;
  v_sum bigint := 0;
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
    description, category, spent_at, created_by, status
  ) values (
    p_id, p_trip_id, p_payer_id, p_amount_cents, p_currency, p_base_cents, p_fx_rate,
    coalesce(p_description, ''), p_category, coalesce(p_spent_at, now()), v_uid,
    'proposed'::expense_status
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

create or replace function commit_expense(p_expense_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_trip_id uuid;
  v_status expense_status;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select e.trip_id, e.status into v_trip_id, v_status
  from expenses e where e.id = p_expense_id;

  if not found then
    raise exception 'expense not found';
  end if;
  if not can_edit_trip_content(v_trip_id) then
    raise exception 'only owner or co-admin may commit proposals';
  end if;
  if not is_trip_writable(v_trip_id) then
    raise exception 'trip is read-only';
  end if;
  if v_status <> 'proposed'::expense_status then
    raise exception 'expense is not proposed';
  end if;

  perform set_config('vamo.expense_rpc', '1', true);
  update expenses
  set status = 'committed'::expense_status
  where id = p_expense_id;
end;
$$;

create or replace function void_expense(p_expense_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_trip_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select e.trip_id into v_trip_id from expenses e where e.id = p_expense_id;
  if not found then
    raise exception 'expense not found';
  end if;
  if not can_edit_trip_content(v_trip_id) then
    raise exception 'only owner or co-admin may void expenses';
  end if;
  if not is_trip_writable(v_trip_id) then
    raise exception 'trip is read-only';
  end if;

  perform set_config('vamo.expense_rpc', '1', true);
  update expenses
  set status = 'cancelled'::expense_status
  where id = p_expense_id
    and status <> 'cancelled'::expense_status;
end;
$$;

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
end;
$$;

revoke all on function propose_expense(uuid, uuid, uuid, bigint, char, bigint, numeric, text, text, timestamptz) from public;
revoke all on function commit_expense(uuid) from public;
revoke all on function void_expense(uuid) from public;
revoke all on function respond_to_share(uuid, boolean, text) from public;

grant execute on function propose_expense(uuid, uuid, uuid, bigint, char, bigint, numeric, text, text, timestamptz) to authenticated;
grant execute on function commit_expense(uuid) to authenticated;
grant execute on function void_expense(uuid) to authenticated;
grant execute on function respond_to_share(uuid, boolean, text) to authenticated;
