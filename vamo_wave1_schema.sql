-- =====================================================================
-- Vamo - Wave 1 schema (SplitTrip + solo capture)
-- Target: Supabase / Postgres. Paste into the SQL editor and run.
-- Money is stored in integer cents. Everything private by default,
-- enforced by Row-Level Security. No money movement (deep-links only).
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------- enums ----------
do $$ begin
  create type member_role   as enum ('owner','member');
  create type member_status as enum ('active','invited','left');
  create type trip_visibility as enum ('private','link','public');
  create type settlement_status as enum ('marked','confirmed');
exception when duplicate_object then null; end $$;

-- ---------- profiles (1:1 with auth.users) ----------
create table if not exists profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null default 'Vamigo',
  avatar_url    text,
  base_currency char(3) not null default 'EUR',
  created_at    timestamptz not null default now()
);

-- auto-create a profile row when a user signs up
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name','Vamigo'))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------- trips ----------
create table if not exists trips (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  destination   text,
  start_date    date,
  end_date      date,
  owner_id      uuid not null references profiles(id),
  base_currency char(3) not null default 'EUR',
  visibility    trip_visibility not null default 'private',
  created_at    timestamptz not null default now()
);

-- ---------- membership ----------
create table if not exists trip_members (
  trip_id   uuid not null references trips(id) on delete cascade,
  user_id   uuid not null references profiles(id) on delete cascade,
  role      member_role   not null default 'member',
  status    member_status not null default 'active',
  joined_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);
create index if not exists idx_members_user on trip_members(user_id);

-- helper: is the current user a member of this trip? (security definer
-- avoids recursive RLS checks when policies reference trip_members)
create or replace function is_trip_member(p_trip uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from trip_members
    where trip_id = p_trip and user_id = auth.uid() and status = 'active'
  );
$$;

-- ---------- invites / join-a-trip ----------
create table if not exists invites (
  id         uuid primary key default gen_random_uuid(),
  trip_id    uuid not null references trips(id) on delete cascade,
  token      text not null unique default encode(gen_random_bytes(9),'base64'),
  created_by uuid not null references profiles(id),
  expires_at timestamptz not null default (now() + interval '30 days'),
  max_uses   int not null default 50,
  uses       int not null default 0,
  created_at timestamptz not null default now()
);

-- join via token; security definer so a non-member can be added safely
create or replace function join_trip(p_token text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_invite invites; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_invite from invites where token = p_token;
  if not found then raise exception 'invalid invite'; end if;
  if v_invite.expires_at < now() then raise exception 'invite expired'; end if;
  if v_invite.uses >= v_invite.max_uses then raise exception 'invite exhausted'; end if;

  insert into trip_members (trip_id, user_id, role, status)
  values (v_invite.trip_id, v_uid, 'member', 'active')
  on conflict (trip_id, user_id)
    do update set status = 'active';

  update invites set uses = uses + 1 where id = v_invite.id;
  return v_invite.trip_id;
end $$;

-- create trip + owner membership atomically (security definer, same pattern as join_trip)
create or replace function create_trip(
  p_id            uuid,
  p_name          text,
  p_destination   text default null,
  p_start_date    date default null,
  p_end_date      date default null,
  p_base_currency char(3) default 'EUR'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_name is null or trim(p_name) = '' then raise exception 'name required'; end if;

  insert into trips (
    id, name, destination, start_date, end_date, owner_id, base_currency
  ) values (
    p_id, trim(p_name), nullif(trim(p_destination), ''),
    p_start_date, p_end_date, v_uid, p_base_currency
  );

  insert into trip_members (trip_id, user_id, role, status)
  values (p_id, v_uid, 'owner', 'active');

  return p_id;
end $$;

revoke all on function create_trip(uuid, text, text, date, date, char) from public;
grant execute on function create_trip(uuid, text, text, date, date, char) to authenticated;

-- ---------- expenses ----------
create table if not exists expenses (
  id            uuid primary key default gen_random_uuid(),
  trip_id       uuid not null references trips(id) on delete cascade,
  payer_id      uuid not null references profiles(id),
  amount_cents  bigint not null check (amount_cents > 0),
  currency      char(3) not null default 'EUR',
  base_cents    bigint not null,                 -- amount converted to trip base currency
  fx_rate       numeric not null default 1,      -- snapshot at spend time
  description   text not null default '',
  category      text,
  spent_at      timestamptz not null default now(),
  created_by    uuid not null references profiles(id),
  created_at    timestamptz not null default now()
);
create index if not exists idx_expenses_trip on expenses(trip_id);

-- each participant's share of an expense (in trip base cents). shares sum to base_cents.
create table if not exists expense_shares (
  id          uuid primary key default gen_random_uuid(),
  expense_id  uuid not null references expenses(id) on delete cascade,
  user_id     uuid not null references profiles(id),
  share_cents bigint not null check (share_cents >= 0),
  unique (expense_id, user_id)
);
create index if not exists idx_shares_expense on expense_shares(expense_id);

-- ---------- settlements (mark/confirm; money moves OUTSIDE Vamo) ----------
create table if not exists settlements (
  id           uuid primary key default gen_random_uuid(),
  trip_id      uuid not null references trips(id) on delete cascade,
  from_user    uuid not null references profiles(id),
  to_user      uuid not null references profiles(id),
  amount_cents bigint not null check (amount_cents > 0),
  currency     char(3) not null default 'EUR',
  status       settlement_status not null default 'marked',
  method       text,            -- 'venmo' | 'paypal' | 'wise' | 'cash' ...
  created_at   timestamptz not null default now()
);
create index if not exists idx_settlements_trip on settlements(trip_id);

-- ---------- derived balances (net position per member, trip base cents) ----------
create or replace view trip_balances as
with paid as (
  select trip_id, payer_id as user_id, sum(base_cents) as paid_cents
  from expenses group by trip_id, payer_id
),
owed as (
  select e.trip_id, s.user_id, sum(s.share_cents) as owed_cents
  from expense_shares s join expenses e on e.id = s.expense_id
  group by e.trip_id, s.user_id
),
settled_out as (
  select trip_id, from_user as user_id, sum(amount_cents) as paid_cents
  from settlements group by trip_id, from_user
),
settled_in as (
  select trip_id, to_user as user_id, sum(amount_cents) as got_cents
  from settlements group by trip_id, to_user
)
select
  m.trip_id, m.user_id,
  coalesce(p.paid_cents,0) - coalesce(o.owed_cents,0)
    + coalesce(so.paid_cents,0) - coalesce(si.got_cents,0) as net_cents
from trip_members m
left join paid p        on p.trip_id=m.trip_id and p.user_id=m.user_id
left join owed o        on o.trip_id=m.trip_id and o.user_id=m.user_id
left join settled_out so on so.trip_id=m.trip_id and so.user_id=m.user_id
left join settled_in si  on si.trip_id=m.trip_id and si.user_id=m.user_id
where m.status='active';
-- net_cents > 0 => the group owes this member; < 0 => this member owes.

-- =====================================================================
-- Row-Level Security
-- =====================================================================
alter table profiles       enable row level security;
alter table trips          enable row level security;
alter table trip_members   enable row level security;
alter table invites        enable row level security;
alter table expenses       enable row level security;
alter table expense_shares enable row level security;
alter table settlements    enable row level security;

-- profiles: anyone authed can read basic profiles (for member display); edit own
create policy profiles_read   on profiles for select using (auth.role() = 'authenticated');
create policy profiles_modify on profiles for update using (id = auth.uid());

-- trips: members can read; any authed user can create (becomes owner); owner edits
create policy trips_read   on trips for select using (is_trip_member(id) or owner_id = auth.uid());
create policy trips_insert on trips for insert with check (owner_id = auth.uid());
create policy trips_update on trips for update using (owner_id = auth.uid());

-- trip_members: members see the roster; you may insert YOURSELF (e.g. as owner on create);
-- general joining goes through join_trip() which is security definer.
create policy members_read   on trip_members for select using (is_trip_member(trip_id));
create policy members_insert on trip_members for insert with check (user_id = auth.uid());

-- invites: members manage invites for their trips
create policy invites_read   on invites for select using (is_trip_member(trip_id));
create policy invites_insert on invites for insert with check (is_trip_member(trip_id) and created_by = auth.uid());

-- expenses / shares / settlements: full access for trip members
create policy expenses_all on expenses for all
  using (is_trip_member(trip_id)) with check (is_trip_member(trip_id));
create policy shares_all on expense_shares for all
  using (exists (select 1 from expenses e where e.id = expense_id and is_trip_member(e.trip_id)))
  with check (exists (select 1 from expenses e where e.id = expense_id and is_trip_member(e.trip_id)));
create policy settlements_all on settlements for all
  using (is_trip_member(trip_id)) with check (is_trip_member(trip_id));

-- =====================================================================
-- Integrity check (run in app or as a scheduled check, not enforced here):
--   for every expense, sum(expense_shares.share_cents) must equal base_cents.
-- =====================================================================
