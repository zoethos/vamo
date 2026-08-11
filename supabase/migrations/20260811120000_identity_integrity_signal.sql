-- Identity-integrity signal: detection only. This never merges auth users.
-- The function returns aggregate counts only so scheduled-job heartbeats do not
-- expose email addresses or user identifiers to authenticated app readers.

create or replace function public.identity_integrity_summary()
returns jsonb
language sql
security definer
set search_path = public, auth
as $$
  with verified_users as (
    select
      id,
      lower(btrim(email)) as normalized_email
    from auth.users
    where email is not null
      and email_confirmed_at is not null
      and btrim(email) <> ''
  ),
  duplicate_verified_emails as (
    select normalized_email, count(*)::integer as account_count
    from verified_users
    group by normalized_email
    having count(*) >= 2
  ),
  duplicate_profiles as (
    select
      users.normalized_email,
      count(profiles.id)::integer as profile_count
    from verified_users users
    join public.profiles profiles on profiles.id = users.id
    group by users.normalized_email
    having count(profiles.id) >= 2
  ),
  apple_private_relay_only as (
    select count(*)::integer as account_count
    from auth.users users
    where lower(coalesce(users.email, '')) like '%@privaterelay.appleid.com'
      and exists (
        select 1
        from auth.identities identities
        where identities.user_id = users.id
          and identities.provider = 'apple'
      )
      and not exists (
        select 1
        from auth.identities identities
        where identities.user_id = users.id
          and identities.provider <> 'apple'
      )
  )
  select jsonb_build_object(
    'duplicate_verified_email_groups',
    (select count(*)::integer from duplicate_verified_emails),
    'duplicate_verified_email_accounts',
    coalesce((select sum(account_count)::integer from duplicate_verified_emails), 0),
    'duplicate_profile_groups',
    (select count(*)::integer from duplicate_profiles),
    'duplicate_profile_accounts',
    coalesce((select sum(profile_count)::integer from duplicate_profiles), 0),
    'apple_private_relay_only_accounts',
    (select account_count from apple_private_relay_only)
  );
$$;

revoke all on function public.identity_integrity_summary() from public;
grant execute on function public.identity_integrity_summary() to service_role;
