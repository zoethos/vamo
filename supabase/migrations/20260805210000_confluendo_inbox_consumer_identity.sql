-- Database-owned environment identity for Vamo cross-environment guards.
--
-- This shared migration intentionally creates no environment row. An owner applies
-- the same schema to both Vamo databases, then performs the environment-specific
-- bootstrap in docs/operations/CONFLUENDO_CONSUMER_IDENTITY_PROMOTION.md. The
-- Confluendo receipt function below is only a least-privilege adapter over this
-- Vamo-wide primitive; it does not own a second identity source.

create table if not exists public.app_environment (
  singleton boolean primary key default true check (singleton),
  environment text not null check (environment in ('staging', 'production')),
  configured_at timestamptz not null default now(),
  configured_by name not null default current_user
);

comment on table public.app_environment is
  'One owner-configured Vamo environment per database. The shared migration never seeds it; cross-environment workers compare it with their independently configured expected environment.';

alter table public.app_environment enable row level security;

revoke all on public.app_environment from public, anon, authenticated, service_role;

do $$
declare
  protected_role text;
begin
  foreach protected_role in array array[
    'confluendo_inbox_writer',
    'confluendo_inbox_apply',
    'confluendo_inbox_apply_app',
    'vamo_canary_app'
  ]
  loop
    if to_regrole(protected_role) is not null then
      execute format('revoke all on table public.app_environment from %I', protected_role);
    end if;
  end loop;
end;
$$;

create or replace function public.current_app_environment()
returns table (environment text)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  return query
  select configured.environment
  from app_environment as configured
  where configured.singleton;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'Vamo app environment is not configured for this database';
  end if;
end;
$$;

revoke all on function public.current_app_environment() from public, anon, authenticated;
grant execute on function public.current_app_environment() to confluendo_inbox_apply;

do $$
begin
  if to_regrole('confluendo_inbox_apply_app') is not null then
    grant execute on function public.current_app_environment() to confluendo_inbox_apply_app;
  end if;
  if to_regrole('vamo_canary_app') is not null then
    grant execute on function public.current_app_environment() to vamo_canary_app;
  end if;
end;
$$;

comment on function public.current_app_environment() is
  'Returns the owner-configured Vamo environment. It fails closed until configured and is the target-side half of every cross-environment guard.';

create or replace function confluendo_inbox.current_consumer_identity()
returns table (
  consumer_key text,
  target_environment text,
  contract_version integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, confluendo_inbox
as $$
begin
  return query
  select
    'vamo'::text,
    configured.environment,
    1::integer
  from public.current_app_environment() as configured;
end;
$$;

revoke all on function confluendo_inbox.current_consumer_identity() from public;
revoke all on function confluendo_inbox.current_consumer_identity() from anon, authenticated;
grant execute on function confluendo_inbox.current_consumer_identity()
  to confluendo_inbox_apply;

do $$
begin
  if to_regrole('confluendo_inbox_apply_app') is not null then
    grant execute on function confluendo_inbox.current_consumer_identity()
      to confluendo_inbox_apply_app;
  end if;
end;
$$;

comment on function confluendo_inbox.current_consumer_identity() is
  'Confluendo receipt adapter over Vamo public.app_environment. It fails closed until the owner configures the database environment.';
