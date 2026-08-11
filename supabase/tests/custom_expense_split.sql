\set ON_ERROR_STOP on

create role authenticated;

create schema auth;
create function auth.uid()
returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create type public.expense_status as enum ('committed');
create type public.share_response as enum ('accepted');

create table public.trips (
  id uuid primary key,
  base_currency char(3) not null
);
create table public.trip_members (
  trip_id uuid not null,
  user_id uuid not null,
  status text not null
);
create table public.expenses (
  id uuid primary key,
  trip_id uuid not null,
  payer_id uuid not null,
  amount_cents bigint not null,
  currency char(3) not null,
  base_cents bigint not null,
  fx_rate numeric,
  description text not null,
  category text,
  spent_at timestamptz not null,
  created_by uuid not null,
  status public.expense_status not null,
  receipt_path text,
  captured_lat double precision,
  captured_lng double precision,
  captured_at timestamptz,
  place_label text,
  place_id uuid,
  fx_rate_source text not null,
  fx_rate_manual numeric,
  fx_conversion_locked boolean not null
);
create table public.expense_shares (
  id uuid primary key,
  expense_id uuid not null,
  user_id uuid not null,
  share_cents bigint not null,
  response public.share_response not null
);

create function public.is_trip_member(uuid)
returns boolean
language sql stable as 'select true';
create function public.is_trip_writable(uuid)
returns boolean
language sql stable as 'select true';

insert into public.trips (id, base_currency)
values ('00000000-0000-0000-0000-000000000001', 'EUR');
insert into public.trip_members (trip_id, user_id, status)
values (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002',
  'active'
);

\ir ../migrations/20260811130000_custom_expense_split.sql

begin;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000002',
  true
);

do $$
declare
  expected_message constant text :=
    'auto base_cents 123 must equal computed 12500';
begin
  begin
    perform public.insert_committed_expense(
      p_id := '00000000-0000-0000-0000-000000000003',
      p_trip_id := '00000000-0000-0000-0000-000000000001',
      p_payer_id := '00000000-0000-0000-0000-000000000002',
      p_amount_cents := 10000,
      p_currency := 'USD'::char(3),
      p_base_cents := 123,
      p_fx_rate := 1.25,
      p_description := 'auto FX invariant smoke'
    );
    raise exception 'auto FX invariant smoke unexpectedly succeeded';
  exception
    when others then
      if sqlerrm <> expected_message then
        raise exception 'expected %, received %', expected_message, sqlerrm;
      end if;
  end;
end;
$$;

reset role;

do $$
begin
  if exists (
    select 1
    from public.expenses
    where id = '00000000-0000-0000-0000-000000000003'
  ) then
    raise exception 'rejected auto FX write persisted an expense';
  end if;
end;
$$;

rollback;
