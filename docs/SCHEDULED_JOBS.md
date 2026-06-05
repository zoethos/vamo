# Scheduled jobs (Wave 2 — S16 decision)

Wave 2 lifecycle features (auto-`unresolved` at 6 months, settle-up nudge) need
a scheduler. Pick **one** path per environment.

## 1. Check pg_cron availability

In the Supabase SQL editor (or `psql`):

```sql
select * from pg_available_extensions where name = 'pg_cron';
select * from pg_extension where extname = 'pg_cron';
```

- **Pro plan + extension enabled:** pg_cron is available. Enable under
  Dashboard → Database → Extensions → `pg_cron`, then schedule:

```sql
select cron.schedule(
  'vamo-heartbeat',
  '0 * * * *',
  $$ select record_job_heartbeat('pg_cron', 'hourly noop'); $$
);
```

Verify:

```sql
select * from job_heartbeats where job_name = 'pg_cron' order by ran_at desc limit 5;
```

- **Free tier / extension unavailable:** use Supabase **scheduled Edge Functions**
  (see below).

## 2. Scheduled Edge Function (fallback / recommended for dev)

Migration `0014_push_devices_and_jobs.sql` creates `job_heartbeats` and
`record_job_heartbeat()` (service_role only).

1. Deploy: `supabase functions deploy scheduled-heartbeat --no-verify-jwt`
2. Dashboard → Edge Functions → `scheduled-heartbeat` → **Schedules** → add cron
   `0 * * * *` (hourly no-op).
3. Confirm rows in `job_heartbeats` with `job_name = 'scheduled-heartbeat'`.

## 3. Trip lifecycle jobs (S17 — daily)

Migration `0015_trip_lifecycle.sql` adds `run_trip_lifecycle_jobs()` (service role).
Deploy the **authenticated** Edge Function (not the bare heartbeat pattern):

```bash
npx supabase secrets set CRON_SECRET='your-long-random-secret'
npx supabase functions deploy trip-lifecycle-jobs --no-verify-jwt
```

Dashboard → Edge Functions → `trip-lifecycle-jobs` → **Schedules** → daily cron
(e.g. `0 6 * * *`). Every request must send header `x-cron-secret: <CRON_SECRET>`.

Jobs (idempotent): day-7 close reminder (`close_warned_at`), day-14 deemed close,
month-5 warn + month-6 `unresolved` for **objected** trips only. Heartbeat:
`job_name = 'trip-lifecycle-jobs'`.

**Never copy `scheduled-heartbeat`'s unauthenticated pattern for real jobs.**

## 4. What S22 will add

| Job | Trigger | Notes |
|-----|---------|-------|
| Settle-up nudge | on close | needs push (R2) + open balances |

Both reuse the same scheduler + `CRON_SECRET` gate.
