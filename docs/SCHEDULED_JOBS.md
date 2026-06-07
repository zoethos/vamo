# Scheduled jobs (Wave 2 — S16/S22)

Wave 2 lifecycle features (auto-`unresolved`, settle-up nudge, per-member close
notice) need a scheduler. Pick **one** path per environment.

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

## 3. Trip lifecycle jobs (S22 — daily, **enable only after device gate**)

Migration `0019_s22_close_notice.sql` updates `run_trip_lifecycle_jobs()` for
**per-member** deemed close (`trip_members.close_notified_at + 14 days`). Push
dispatch lives in the Edge Function (service-role, member-targeted FCM).

Deploy:

```bash
npx supabase secrets set CRON_SECRET='your-long-random-secret'
npx supabase secrets set FIREBASE_SERVICE_ACCOUNT='…'
npx supabase functions deploy trip-lifecycle-jobs --no-verify-jwt
```

**Do not schedule until S25 device pass + manual cron dry-run are green**
(see `docs/slices/S22_PROMPT.md` §8). When ready:

Dashboard → Edge Functions → `trip-lifecycle-jobs` → **Schedules** → daily cron
(e.g. `0 6 * * *`). Every request must send header `x-cron-secret: <CRON_SECRET>`.

Manual dry-run:

```bash
curl -X POST "$SUPABASE_URL/functions/v1/trip-lifecycle-jobs" \
  -H "x-cron-secret: $CRON_SECRET"
```

Cron moments (idempotent, per-member where noted):

| Moment | Condition | Push copy (title only on lock screen) |
|--------|-----------|----------------------------------------|
| Close notice | `closing` + member `close_notified_at` null | Trip is closing — review… |
| Day-7 reminder | `close_notified_at + 7d`, not acted, single-shot | **7 days left** to review… |
| Deemed closed | trip → `closed` (all members acted-or-notified+14d) | Trip closed. Settle up… |
| Settle nudge | member has marked settlement, single-shot | Balance to settle in… |

In-app fallback: `stamp_close_notice_viewed(trip_id)` stamps notice when a member
opens a closing trip (no push device required).

Heartbeat: `job_name = 'trip-lifecycle-jobs'`.

**Never copy `scheduled-heartbeat`'s unauthenticated pattern for real jobs.**

## 4. Shared FCM helper

`supabase/functions/_shared/fcm.ts` is used by `send-push` and
`trip-lifecycle-jobs`. Both require frozen `deno.lock` and pass `deno check` in CI.
