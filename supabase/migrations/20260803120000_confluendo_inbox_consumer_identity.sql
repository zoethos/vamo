-- Consumer-owned identity attestation for Confluendo inbox apply receipts.
--
-- The value is deliberately a Vamo contract, not a Confluendo configuration
-- secret. It lets a delivery worker verify that its least-privilege apply DSN
-- reached the reviewed Vamo Production inbox before reporting success.

create or replace function confluendo_inbox.current_consumer_identity()
returns table (
  consumer_key text,
  target_environment text,
  contract_version integer
)
language sql
stable
set search_path = pg_catalog, confluendo_inbox
as $$
  select
    'vamo'::text,
    'production'::text,
    1::integer;
$$;

revoke all on function confluendo_inbox.current_consumer_identity() from public;
revoke all on function confluendo_inbox.current_consumer_identity() from anon, authenticated;
grant execute on function confluendo_inbox.current_consumer_identity() to confluendo_inbox_apply;

do $$
begin
  if to_regrole('confluendo_inbox_apply_app') is not null then
    grant execute on function confluendo_inbox.current_consumer_identity()
      to confluendo_inbox_apply_app;
  end if;
end;
$$;

comment on function confluendo_inbox.current_consumer_identity() is
  'Vamo-owned non-secret consumer identity used to attest Confluendo inbox apply receipts.';
