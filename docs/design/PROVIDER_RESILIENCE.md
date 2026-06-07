# Provider resilience — throttling, quotas & observability

Status: design standard · 2026-06-05 · applies to **every** external provider
(see `docs/DEPENDENCIES.md`).

## Why (the scar-tissue lesson)

Every external API is **throttle-prone** (429 / Retry-After) and
**quota-bounded** (per-second, daily, monthly, or contract caps). The classic
failure — seen repeatedly in MS Graph support: throttling happens silently, no
one has visibility, the app hits a wall blind, and the *root cause (a contract
/ plan limit) is invisible* until someone digs. We caught our own version on
the first try: exchangerate.host returned **429** on the 2nd FX call in a smoke
run — a free-tier rate limit.

The fix is two layers: **handle** throttles gracefully at runtime, and
**observe** them (and quota burn) so we react *before* users do. The second is
what the internal dashboard exists to surface.

## Layer 1 — runtime handling (every provider call)

Behind the provider abstraction seam (so it's uniform, not per-call):

1. **Respect `Retry-After`.** On 429, honor the header's backoff — never
   blind-retry into the limit.
2. **Backoff with jitter** for transient throttles; capped attempts.
3. **Distinguish transient-429 from quota-exhausted.** Transient → retry.
   Quota/contract exhausted → do NOT retry; degrade + alert.
4. **Circuit-breaker.** After N consecutive throttles, open the circuit: stop
   hammering, serve degraded (cache / last-known), recover later.
5. **Cache to avoid the call.** Many calls are avoidable — FX rates are the
   prime example: a captured constant rate is valid for the trip; don't
   re-fetch. Caching is the cheapest throttle defense.
6. **Fail loud and safe.** A throttle surfaces as a catalogued `action_failed`
   (no vendor/exception leak), never corrupts data, never silently wrong.
   (S20 FX already meets this interim bar.)

## Layer 2 — observability (what the dashboard catches)

1. **Structured throttle/quota telemetry** on every 429/quota response:
   `{provider, endpoint, status, retry_after_s, ts}` — no secrets, no PII.
   Analytics event e.g. `provider_throttled`.
2. **Persisted incident log** (a table, service-role write) so trends survive
   beyond ephemeral analytics — the dashboard and the quarterly review read it.
3. **Quota-burn tracking vs documented ceilings.** Each provider's limits live
   in `DEPENDENCIES.md` (cost-watch). Telemetry tracks *actual* call volume
   against them → early warning ("80% of monthly quota", "sustained 429s").
4. **Dashboard panel** (the internal ops console, W3): per-provider health,
   quota burn %, recent throttle events, last incident. This is the concrete
   substance of the "flight-control dashboard" ask — react timely, no ticket
   surprises.

## Per-provider applicability

| Provider | Throttle/quota risk | Primary defense |
|---|---|---|
| exchangerate.host (FX) | tight free-tier rate + monthly cap | **cache** (constant rate per trip — rarely re-fetch) + backoff; telemetry on 429 |
| Supabase | connection pool, fn invocation limits, plan caps | offline-first buffer; watch fn/egress quota |
| PostHog | event volume cap | batch/sample if near cap; volume telemetry |
| Brevo | daily send cap | queue + backoff; **cap-approach alert is critical** (OTP SPOF) |
| FCM | effectively unlimited | n/a |
| Vercel | bandwidth (plan) | CDN cache; watch at launch |
| OpenAI (S23) | 429/5xx/timeout + usage budget | global cache, strict schema, bounded wait, fallback theme; log `provider_throttled` |

## Phasing (don't over-build now)

- **Interim (now):** fail loud + safe + no corruption. S20 FX already does
  this — a 429 raises a catalogued error, existing rates/expenses untouched.
  **Acceptable to ship.**
- **Target (W3 / FX Edge-Function refactor + abstraction layer + dashboard):**
  full Layer-1 handling behind the seam + Layer-2 telemetry + dashboard panel.
  Build it *with* the abstraction layer (one seam, applied to all providers) —
  not piecemeal.

## Standard for new integrations

Any new external provider must, at integration time: declare its limits in
`DEPENDENCIES.md`, route through the abstraction seam (inherits Layer-1), and
emit the throttle telemetry (Layer-2). No raw, unguarded, unobserved external
calls.
