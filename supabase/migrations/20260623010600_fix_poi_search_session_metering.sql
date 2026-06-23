-- Correct POI quota counters inflated by metering each search keystroke.
--
-- Before 2026-06-23, poi-discovery used:
--   poi:search:<user_id>:<session_id>:<query_cache_hash>
-- as the reservation idempotency key. That meant one typed search session could
-- create multiple completed reservations as the query changed. The edge
-- function now meters search by session, so historical counters need to be
-- reduced to one fresh call per user/session/provider/month.

with search_session_overages as (
  select
    service,
    provider,
    user_id,
    period_month,
    split_part(idempotency_key, ':', 4) as search_session_id,
    greatest(count(*) - 1, 0)::integer as overage
  from public.service_usage_reservations
  where service = 'poi'
    and idempotency_key like 'poi:search:%:%:%'
    and status in ('reserved', 'completed')
  group by service, provider, user_id, period_month, split_part(idempotency_key, ':', 4)
  having count(*) > 1
),
user_overages as (
  select service, user_id, period_month, sum(overage)::integer as overage
  from search_session_overages
  group by service, user_id, period_month
)
update public.service_usage_user usage
set fresh_calls = greatest(usage.fresh_calls - user_overages.overage, 0),
    updated_at = now()
from user_overages
where usage.service = user_overages.service
  and usage.user_id = user_overages.user_id
  and usage.period_month = user_overages.period_month;

with search_session_overages as (
  select
    service,
    provider,
    user_id,
    period_month,
    split_part(idempotency_key, ':', 4) as search_session_id,
    greatest(count(*) - 1, 0)::integer as overage
  from public.service_usage_reservations
  where service = 'poi'
    and idempotency_key like 'poi:search:%:%:%'
    and status in ('reserved', 'completed')
  group by service, provider, user_id, period_month, split_part(idempotency_key, ':', 4)
  having count(*) > 1
),
global_overages as (
  select service, provider, period_month, sum(overage)::integer as overage
  from search_session_overages
  group by service, provider, period_month
)
update public.service_usage_global usage
set fresh_calls = greatest(usage.fresh_calls - global_overages.overage, 0),
    updated_at = now()
from global_overages
where usage.service = global_overages.service
  and usage.provider = global_overages.provider
  and usage.period_month = global_overages.period_month;
