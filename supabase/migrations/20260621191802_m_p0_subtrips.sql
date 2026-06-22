-- M-P0 — Subtrips: private per-cohort planning lanes inside a trip.
--
-- P0 read model is deliberately broad: all active trip members can read
-- subtrips and their items. Writes are narrower: owner/co-admin can edit any
-- trip plan item; regular members can write items only in subtrips they belong
-- to. Subtrip creation goes through an RPC so member validation is atomic.

alter table public.trips
  add column if not exists subtrips_enabled boolean not null default false;

create table if not exists public.subtrips (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 80),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_subtrips_trip
  on public.subtrips(trip_id, created_at);

create table if not exists public.subtrip_members (
  subtrip_id uuid not null references public.subtrips(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (subtrip_id, user_id)
);

create index if not exists idx_subtrip_members_user
  on public.subtrip_members(user_id);

alter table public.trip_plan_items
  add column if not exists subtrip_id uuid references public.subtrips(id)
    on delete set null;

create index if not exists idx_trip_plan_items_subtrip
  on public.trip_plan_items(subtrip_id, position);

alter table public.subtrips enable row level security;
alter table public.subtrip_members enable row level security;

grant select, insert, update, delete on table public.subtrips
  to anon, authenticated;
grant select, insert, update, delete on table public.subtrip_members
  to anon, authenticated;
grant select, insert, update, delete on table public.trip_plan_items
  to anon, authenticated;
grant select, insert, update on table public.trips
  to anon, authenticated;

create or replace function public.is_subtrip_member(p_subtrip_id uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1
    from public.subtrip_members sm
    join public.subtrips s on s.id = sm.subtrip_id
    where sm.subtrip_id = p_subtrip_id
      and sm.user_id = auth.uid()
      and public.is_trip_member(s.trip_id)
  );
$$;

revoke all on function public.is_subtrip_member(uuid) from public;
grant execute on function public.is_subtrip_member(uuid) to authenticated;

create or replace function public.can_edit_plan_item_scope(
  p_trip_id uuid,
  p_subtrip_id uuid
) returns boolean
language sql security definer stable set search_path = public as $$
  select public.can_edit_trip_content(p_trip_id)
    or (
      p_subtrip_id is not null
      and public.is_subtrip_member(p_subtrip_id)
    );
$$;

revoke all on function public.can_edit_plan_item_scope(uuid, uuid) from public;
grant execute on function public.can_edit_plan_item_scope(uuid, uuid)
  to authenticated;

create or replace function public.trip_plan_items_subtrip_guard()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_subtrip_trip_id uuid;
begin
  if new.subtrip_id is null then
    return new;
  end if;

  select s.trip_id into v_subtrip_trip_id
  from public.subtrips s
  where s.id = new.subtrip_id;

  if v_subtrip_trip_id is null then
    raise exception 'subtrip not found';
  end if;

  if v_subtrip_trip_id <> new.trip_id then
    raise exception 'subtrip belongs to a different trip';
  end if;

  return new;
end;
$$;

drop trigger if exists trip_plan_items_subtrip_guard_trg
  on public.trip_plan_items;
create trigger trip_plan_items_subtrip_guard_trg
  before insert or update on public.trip_plan_items
  for each row execute function public.trip_plan_items_subtrip_guard();

drop policy if exists subtrips_select on public.subtrips;
create policy subtrips_select on public.subtrips
  for select using (public.is_trip_member(trip_id));

drop policy if exists subtrips_block_insert on public.subtrips;
create policy subtrips_block_insert on public.subtrips
  for insert with check (false);

drop policy if exists subtrips_block_update on public.subtrips;
create policy subtrips_block_update on public.subtrips
  for update using (false) with check (false);

drop policy if exists subtrips_block_delete on public.subtrips;
create policy subtrips_block_delete on public.subtrips
  for delete using (false);

drop policy if exists subtrip_members_select on public.subtrip_members;
create policy subtrip_members_select on public.subtrip_members
  for select using (
    exists (
      select 1
      from public.subtrips s
      where s.id = subtrip_id
        and public.is_trip_member(s.trip_id)
    )
  );

drop policy if exists subtrip_members_block_insert on public.subtrip_members;
create policy subtrip_members_block_insert on public.subtrip_members
  for insert with check (false);

drop policy if exists subtrip_members_block_update on public.subtrip_members;
create policy subtrip_members_block_update on public.subtrip_members
  for update using (false) with check (false);

drop policy if exists subtrip_members_block_delete on public.subtrip_members;
create policy subtrip_members_block_delete on public.subtrip_members
  for delete using (false);

drop policy if exists trip_plan_items_insert on public.trip_plan_items;
create policy trip_plan_items_insert on public.trip_plan_items
  for insert with check (
    public.is_trip_member(trip_id)
    and public.is_trip_writable(trip_id)
    and public.can_edit_plan_item_scope(trip_id, subtrip_id)
  );

drop policy if exists trip_plan_items_update on public.trip_plan_items;
create policy trip_plan_items_update on public.trip_plan_items
  for update
  using (public.is_trip_member(trip_id))
  with check (
    public.is_trip_member(trip_id)
    and public.is_trip_writable(trip_id)
    and public.can_edit_plan_item_scope(trip_id, subtrip_id)
  );

drop policy if exists trip_plan_items_delete on public.trip_plan_items;
create policy trip_plan_items_delete on public.trip_plan_items
  for delete using (
    public.is_trip_member(trip_id)
    and public.can_edit_plan_item_scope(trip_id, subtrip_id)
  );

create or replace function public.create_subtrip(
  p_trip_id uuid,
  p_name text,
  p_member_ids uuid[]
) returns public.subtrips
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_enabled boolean;
  v_member_ids uuid[];
  v_invalid uuid[];
  v_subtrip public.subtrips;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if v_name = '' then
    raise exception 'subtrip name required';
  end if;
  if length(v_name) > 80 then
    raise exception 'subtrip name too long';
  end if;
  if not public.is_trip_member(p_trip_id) then
    raise exception 'not a trip member';
  end if;
  if not public.is_trip_writable(p_trip_id) then
    raise exception 'trip is not writable';
  end if;

  select t.subtrips_enabled into v_enabled
  from public.trips t
  where t.id = p_trip_id;

  if not found then
    raise exception 'trip not found';
  end if;
  if not coalesce(v_enabled, false) then
    raise exception 'subtrips are disabled';
  end if;

  select array_agg(distinct id order by id) into v_member_ids
  from (
    select unnest(coalesce(p_member_ids, array[]::uuid[])) as id
    union
    select v_uid as id
  ) members
  where id is not null;

  select array_agg(id order by id) into v_invalid
  from unnest(v_member_ids) as ids(id)
  where not exists (
    select 1
    from public.trip_members tm
    where tm.trip_id = p_trip_id
      and tm.user_id = ids.id
      and tm.status = 'active'
  );

  if v_invalid is not null then
    raise exception 'subtrip member is not an active trip member';
  end if;

  insert into public.subtrips (trip_id, name, created_by)
  values (p_trip_id, v_name, v_uid)
  returning * into v_subtrip;

  insert into public.subtrip_members (subtrip_id, user_id)
  select v_subtrip.id, id
  from unnest(v_member_ids) as ids(id);

  return v_subtrip;
end;
$$;

revoke all on function public.create_subtrip(uuid, text, uuid[]) from public;
grant execute on function public.create_subtrip(uuid, text, uuid[])
  to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.subtrips;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.subtrip_members;
exception when duplicate_object then null;
end $$;
