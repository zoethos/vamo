# Cycle 2 Observability Runbook

Use this before widening tester access. It pairs a deterministic staging
scenario with a light k6 load pass, then tells you what to watch.

## Preconditions

- Run against staging/non-prod only.
- Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` for the target project.
- Use dedicated scenario users when possible:
  - `SCENARIO_USER_A_EMAIL` / `SCENARIO_USER_A_PASSWORD`
  - `SCENARIO_USER_B_EMAIL` / `SCENARIO_USER_B_PASSWORD`
- The scripts fall back to `RLS_USER_A/B_*` if dedicated users are not set.
- Keep service-role keys out of k6. Load tests use normal authenticated users.

## Deterministic Scenario

```powershell
$env:SCENARIO_TARGET_LABEL = "staging"
dart run tool/scenario_sim.dart
```

Expected result: JSON with `"ok": true`, a `run_id`, a `trip_id`, and zero
failed checks. The trip is intentionally left in staging with a `C2 scenario`
name so it can be inspected and cleaned up manually.

This checks:
- password auth for two users
- `create_trip`
- invite insert + `join_trip`
- `insert_committed_expense`
- `propose_expense` + `commit_expense`
- `amend_expense_conversion`
- member expense visibility
- `trip_balances` zero-sum invariant

## k6 Hot-Path Load

Install k6 locally, then run:

```powershell
$env:K6_TARGET_LABEL = "staging"
k6 run tool/k6/vamo_hot_paths.js
```

Useful knobs:

```powershell
$env:K6_TARGET_LABEL = "staging"
$env:K6_VUS = "2"
$env:K6_DURATION = "1m"
$env:K6_ITER_SLEEP_SECONDS = "1"
k6 run tool/k6/vamo_hot_paths.js
```

Defaults are intentionally small: two virtual users for one minute. Increase in
small steps only after the baseline is green.

The k6 pass exercises:
- password auth token exchange
- `create_trip`
- invite insert + `join_trip`
- `insert_committed_expense`
- `propose_expense` + `commit_expense`
- expense and balance reads through RLS

The script refuses to run unless `K6_TARGET_LABEL` includes `staging`, unless
`K6_ALLOW_NON_STAGING=true` is explicitly set.

## Watch During The Run

Supabase:
- API request error rate and latency
- Auth logs for throttling or abnormal sign-in failures
- Postgres CPU, memory, connections, and slow queries
- Edge Function logs only if a run intentionally touches function-backed paths
- Storage egress if media paths are added later

App telemetry:
- PostHog `action_failed` count and `error_kind` mix
- Crashlytics new fatal events by app version
- Firebase push delivery only for notification-specific runs

Repo-local output:
- k6 `http_req_failed` below 5%
- k6 p95 HTTP duration below 1500ms
- k6 checks above 95%
- scenario simulator `"ok": true`

## Stop Conditions

Stop the run if any of these happen:
- sustained 5xx responses from Supabase
- auth throttling blocks the scenario users
- Postgres connections approach the project limit
- p95 API latency stays above 3 seconds for more than one minute
- `action_failed` spikes with `server`, `auth`, or `network` kinds

## Pass Criteria

Cycle 2 scenario/load is green when:
- deterministic scenario passes once on staging
- k6 baseline passes at the default load
- one modest ramp, for example `K6_VUS=5 K6_DURATION=3m`, stays under thresholds
- no new Crashlytics fatal events appear for the tested build
- no Supabase dashboard warnings require immediate mitigation

## Notes

- These tools intentionally create staging data. Prefer a staging project or
  dedicated test users, then clean up by trip name/run id from the dashboard.
- Do not run the k6 script against production during closed beta without an
  explicit load window and `K6_ALLOW_NON_STAGING=true`.
- If the target project is still on a free tier, keep the first pass tiny. The
  goal is early failure discovery, not maximum throughput.
