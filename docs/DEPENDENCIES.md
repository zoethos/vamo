# Dependencies register

One place to track what Vamo depends on, why, what it costs, how locked-in we
are, and what we'd switch to. Review **quarterly** and whenever a provider
changes pricing/terms or a dependency blocks a slice.

Columns: **Lock-in** = how hard to swap (low/med/high). **Review trigger** =
the event that should make us revisit. Keep entries honest — "inherited" is a
valid reason, but flag it.

> **Why this doc is load-bearing.** Every external service is simultaneously
> an **uncontrolled failure point** (our uptime depends on theirs) and a
> **cost center** (their pricing dictates ours). We don't control any of them.
> So this register is a risk instrument, not a parts list: for each dependency
> we track its **blast radius** (what breaks if it dies), how the app
> **degrades**, and where we're **under-mitigated**. See *Resilience posture*
> and *Cost watch* below.
>
> **Throttling & quotas** are a first-class concern (silent throttle → blind
> wall → ticket storm, the MS Graph pattern). Handling + observability standard:
> `docs/design/PROVIDER_RESILIENCE.md`. The documented limits below feed the
> quota-burn tracking the internal dashboard will surface.

---

## Resilience posture — failure modes & blast radius

Tiers: **T0 critical-path** (core app unusable / sign-in blocked) · **T1
degraded** (a feature breaks, app still works) · **T2 background** (no runtime
impact).

| Dep | Tier | If it's DOWN | Current cushion | Under-mitigated? |
|---|---|---|---|---|
| **Supabase** | **T0** | No sign-in, no sync, no cloud reads | **Offline-first Drift cache + sync outbox** absorbs *transient* outages — app keeps working locally, syncs on recovery | **Sustained** outage has no fallback (single-vendor concentration: DB+auth+storage+functions). Accepted risk; document the daily-backup + restore path. |
| **Brevo** (OTP email) | **T0** | OTP codes don't arrive → **nobody new can sign in**; existing sessions survive | `send-auth-email` now falls back to **Resend** after Brevo failure | Only until `RESEND_API_KEY` is provisioned and the function is deployed — code path exists, ops secret activates it. |
| **FCM** (push) | T1 | Notifications silently fail | app fully usable; lifecycle/nudges just don't ping | OK. Pruning UNREGISTERED tokens (S22) is the only hygiene gap. |
| **Firebase Crashlytics** | T1 | Crash reports delayed/lost | app keeps running; testers can still report manually | OK. Firebase console is the crash source of truth; PostHog remains product telemetry. |
| **exchangerate.host** (FX) | T1 | Can't add/refresh a currency rate | **Forward-only design**: existing trips keep stored rates; capture fails *loudly* (catalogued error), nothing corrupts | OK by design. The in-DB `http` blocking-RPC risk is the real concern, not data safety — tracked for Edge-Function refactor. |
| **PostHog** | T1 | Analytics events lost | app fine; debug-console fallback exists; gate metrics blind for the gap | OK — but the Wave-2→3 gate *reads* PostHog, so a long outage delays the decision, not the app. |
| **MLKit OCR** | T1 | — | **on-device, no network** — resilient by design; receipt scan works offline | None. Keep it on-device (also a privacy promise). |
| **Vercel** (site) | T1 | Invite landing `/j/`, privacy URL, assetlinks down | QR/link invites degrade to manual entry; app core unaffected | OK. assetlinks outage breaks App-Links verification (links open browser, not app). |
| **Theme AI provider** (S23 theme miss path; default direct OpenAI) | T2 | New destinations fall back to the default/local theme pack | cache-first design; existing `trips.theme` values and built-in fallback still render | Provision `THEME_AI_API_KEY` before S23; log throttles/timeouts and never block trip creation. |
| **ImprovMX** | T2 | Inbound `@vamo.world` mail not forwarded | no app impact | None. |
| **GoDaddy** (registrar) | T2 | only at renewal / DNS edits | DNS served by Vercel; registrar is dormant at runtime | Set auto-renew; calendar the expiry. |
| **Google Play** | T2 | distribution channel | doesn't affect running installs | None. |

**Design principles that keep blast radius low (keep honoring these):**
1. **Offline-first is our resilience layer.** Drift + outbox means transient
   backend outages degrade to "syncs later," not "app broken." Every new write
   path should go through the outbox, not direct RPC, unless deliberately
   online-only (governance actions are the documented exception).
2. **Insulate behind seams we own.** Analytics event names, `FxRatesClient`,
   the labels bundles — these make swaps cheap. New integrations get a thin
   interface we control, so a provider change is a one-file swap, not a
   refactor. (Supabase is the deliberate exception — too deep to abstract;
   we accept the coupling and manage it via backups.)
3. **Fail loud and catalogued, never silent or raw.** A dependency failure
   surfaces as a catalogued `action_failed` (no vendor/exception leak), and
   never corrupts stored data (FX forward-only is the template).

---

## Cost watch — free-tier ceilings & first paid step

Cost scales with **users** on three services — Supabase, PostHog, Brevo —
those are the ones to watch as testers grow. The rest are flat or trivial.

| Dep | Free ceiling (verify at review) | First paid step | Scaling driver | Watch signal |
|---|---|---|---|---|
| **Supabase** | Free project limits (DB size, egress, MAU, fn invocations) | Pro ~$25/mo (planned at launch) | MAU + storage (receipt images!) + function calls | receipt storage growth; MAU near free cap |
| **PostHog** | ~1M events/mo (EU) | usage-based | event volume × users | monthly event count trend |
| **Brevo / Resend** | Brevo ~300 emails/day; Resend tier TBD | paid tier | sign-ins + notifications | daily OTP+notify volume near cap; fallback usage > 0 |
| **FCM** | effectively free | — | — | n/a |
| **exchangerate.host** (FX) | free request cap; tight burst rate limit | paid | **negligible** (1 capture/currency/trip) | watch for 429s; smoke must not make repeated live calls |
| **Vercel** | Hobby free | Pro ~$20/mo (planned) | bandwidth | launch traffic |
| **Theme AI provider** | usage-based small-model calls | usage-based | distinct uncached destinations only | cache-miss count + `provider_throttled` + provider usage ledger |
| **Domain** | — | ~$20/yr | — | renewal date |
| **Play** | — | $25 one-time | — | paid once |

**Launch cost floor (rough):** Supabase Pro + Vercel Pro ≈ $45/mo + domain.
Everything else stays free until user volume pushes PostHog/Brevo over their
caps — which is the signal to budget the next tier, not a surprise.

---

## External services & APIs

| Service | Role | Auth / secret | Cost tier | Lock-in | Review trigger |
|---|---|---|---|---|---|
| **Supabase** | Postgres + RLS, auth, storage, Edge Functions, Vault, realtime, pg_cron | project keys (anon/publishable + service/secret); never ship service key | Free now → Pro at launch | **High** — the backbone | scaling limits; Pro pricing at launch |
| **PostHog (EU)** | Product analytics (funnel + signals) | `POSTHOG_API_KEY` (project 193638, EU host) | Free tier (event volume cap) | Med — event names are ours; SDK swappable | event volume nears free cap; pricing |
| **Brevo** | Primary transactional email (OTP sign-in codes, notifications) | API key; sender `noreply@vamo.world` pending | Free tier (daily send cap) | Low-med — `send-auth-email` uses provider adapter | daily send cap; deliverability issues |
| **Resend** | Fallback transactional email for OTP sign-in codes | `RESEND_API_KEY`; optional `RESEND_SENDER_EMAIL` | Free/paid tier TBD | Low — same provider adapter + HTML payload | any fallback usage; Brevo outage; quota/pricing |
| **Firebase / FCM / Crashlytics** | Push notifications (HTTP v1) + Android crash diagnostics | `FIREBASE_SERVICE_ACCOUNT` JSON (Supabase secret for FCM); Android app uses `google-services.json` | Free (FCM); Crashlytics free tier | Med-high — token plumbing + client SDK | APNs/iOS work; SDK major bumps; verify crash upload on tester builds |
| **exchangerate.host** (FX) | FX market rates → trip constant table (D4) | `exchangerate_access_key` (Supabase **Vault**) | Free tier (keyed) | **Low** — see FX card | endpoint corrected to `/live` 2026-06-05; key rotation; free-tier source-lock |
| **Vercel** | Web tier hosting (`apps/site`: landing, privacy, `/j/` invite, assetlinks) + DNS panel | account (personal → Pro at launch) | Hobby now | Med — Next.js portable; DNS records re-point | Pro at launch; team transfer |
| **Theme AI provider** | S23 AI theme generation on cache miss; default direct OpenAI, Azure-compatible later | `THEME_AI_*` config/secrets as Supabase Edge Function secrets; never client-side | usage-based; expected negligible due global cache | Low-med — schema prompt, validation, and adapter are ours | model/pricing changes; sustained 429/5xx; output quality review; dashboard switch criteria |
| **ImprovMX** | Inbound email forwarding (`*@vamo.world` → zoethos@outlook.com) | MX records | Free | Low | volume; want real mailboxes |
| **GoDaddy** | Domain registrar (`vamo.world`) | account | ~annual | Low | renewal; transfer to Vercel/Cloudflare |
| **Google Play** | Android distribution (internal track → production) | Play Console | $25 one-time | High (Android channel) | store policy; signing |
| **pgsql-http (`http` ext)** | In-DB HTTP for FX capture (S20) | n/a (DB extension) | n/a | **Low** — flagged for removal | ⚠️ retire in FX Edge-Function refactor |

### Apple / iOS
Not yet provisioned. TestFlight + APNs are a known gap (`SHIP_INTERNAL.md`).
Add a row when iOS work starts.

---

## Watched cards (the ones that need eyes)

### FX provider — exchangerate.host (decided; endpoint corrected 2026-06-05)
- **Provider:** exchangerate.host, as decided (key in Vault). NOT switched —
  an earlier attempt to swap to Frankfurter was reverted (it overrode a settled
  decision; provider swap stays a *deferred option*, not done).
- **What broke & fix:** 0019 used the OLD endpoint `/latest?base=` → 404 on the
  revamped apilayer API. Fixed in `0020` to the current `/live?currencies=…`
  returning `quotes{}`, **pivoting through the default USD source** (non-USD
  source is plan-gated; USD pivot still covers all 168 ccy + any trip base).
- **Coverage:** 168 currencies (broad — the reason to stay keyed vs ECB-only).
- **Rate-limit reality:** free tier can 429 on back-to-back requests. Product
  volume is still fine (one capture/currency/trip, occasional refresh), but
  smoke makes only one live provider call and tests refresh invariants via the
  service-role `_apply_trip_fx_rate` writer.
- **Still open (deferred, tracked):** the in-DB `http` fetch is a blocking-RPC
  under a DB connection — move to the `fx-rates` Edge Function before public
  launch (`MONEY_GOVERNANCE.md` D4 follow-up). The provider re-eval (Frankfurter
  = keyless ECB ~30 ccy as a fallback/simplification) rides with that refactor
  if ever wanted — **not** a mid-slice swap.

### Riverpod / go_router major versions
- Pinned: `flutter_riverpod` 2.6.1 (v3 available), `go_router` 14.8.1 (17.x
  available). Both are **major** upgrades with breaking changes; go_router in
  particular bit us once (the GoException deep-link saga). Don't drift-upgrade
  casually — schedule as a dedicated chore with full smoke + the deep-link
  router tests green.

---

## Key packages (architecturally significant)

Not every transitive dep — only the ones with real lock-in or risk.

| Package | Role | Lock-in | Note |
|---|---|---|---|
| `drift` / `drift_flutter` | Local offline-first DB + schema versioning | High | schema vN migrations are load-bearing; every slice bumps it |
| `supabase_flutter` (+ gotrue, storage_client, functions_client) | Backend client | High | tied to Supabase |
| `flutter_riverpod` | State management | High | v3 upgrade pending (see card) |
| `go_router` | Routing + deep links | Med | v17 pending; deep-link tests guard it |
| `mobile_scanner` | QR invite scan (S15) | Low | swappable |
| `google_mlkit_text_recognition` | **On-device** OCR (privacy claim) | Med | on-device is a privacy promise — keep it on-device |
| `geocoding` | Place resolution | Low | |
| `firebase_core` / `firebase_messaging` / `firebase_crashlytics` | Push + crash reports | Med-high | tied to Firebase; Android-only until iOS is provisioned |
| `video_player` | In-app playback for captured trip videos (S30) | Low-med | avoids fragile external `file://` handoff for private app files; thumbnail generation remains deferred |
| `posthog_flutter` | Analytics SDK | Low-med | event names are ours |
| `app_links` | Deep-link channel (single handler) | Med | never re-add engine deep-linking alongside |
| `flutter_slidable` | Swipe edit/delete on list rows (S38) | Low | two-action panes + a11y long-press fallback |
| `share_plus`, `qr_flutter`, `package_info_plus`, `flutter_dotenv`, `image`, `connectivity_plus` | Misc utilities | Low | |
| `url_launcher` | SMS/email compose for S26 contact invite (`sms:` / `mailto:`) | Low | Android `<queries>` for sms/mailto only; no broad contacts permission |

**Upgrade debt:** CI reports ~41 packages with newer versions behind current
constraints. Most are minor. Do a batched dependency-bump chore periodically
(separate branch, full `melos run ci` + cloud smoke) rather than ad-hoc bumps —
and treat Riverpod/go_router/Firebase majors as their own scoped chores.

---

## Secrets inventory (where each lives — never commit values)

| Secret | Lives in | Used by |
|---|---|---|
| Supabase anon/publishable key | `app/.env` | app client |
| Supabase service/secret key | local smoke runner (gitignored), CI env | `rls_smoke.dart`, never the app |
| `POSTHOG_API_KEY` | `app/.env` | analytics |
| `FIREBASE_SERVICE_ACCOUNT` | Supabase secret | `send-push` |
| `CRON_SECRET` | Supabase secret | `trip-lifecycle-jobs` |
| `exchangerate_access_key` | Supabase **Vault** | `_fetch_market_fx_rate` |
| `THEME_AI_API_KEY` | Supabase Edge Function secret | `resolve-theme` (S23); server-only theme AI provider key |
| `BREVO_API_KEY` | Supabase Edge Function secret | `send-auth-email` primary OTP/email provider |
| `SENDER_EMAIL` | Supabase Edge Function secret | verified sender address for primary and fallback email |
| `RESEND_API_KEY` | Supabase Edge Function secret | `send-auth-email` fallback OTP/email provider |
| `RESEND_SENDER_EMAIL` | Supabase Edge Function secret (optional) | fallback sender override; defaults to `SENDER_EMAIL` |

Rule (CONTRIBUTING): local-secret files are gitignored the moment they're
created, not when they receive a value.

---

## Accounts & ownership (the "which account?" map — identifiers, not secrets)

We juggle a few identities; write down which owns what so it's never a guess.

| Purpose | Account / identity | Notes |
|---|---|---|
| **Google Play publisher** | `troccadev@gmail.com` — Personal account | Dev name = `Vamo — Trips Together` (or chosen variant). **Verification pending** (Jun 2026). Personal→Org not switchable in place: migrate via **app transfer** once the Estonia company is registered (D-U-N-S required for Org). |
| **Firebase / GCP `vamo-world`** | `troccadev@gmail.com` — **Owner** | Same Google identity as Play (deliberate — keeps Android+Firebase+Play aligned). Owns FCM, service account, push. |
| **Public developer contact** | `support@vamo.world` | Shown on the Play profile **only at production** (not during internal testing). Forwards via ImprovMX → `zoethos@outlook.com`. |
| **Project comms / mail forward target** | `zoethos@outlook.com` | ImprovMX `*@vamo.world` catch-all delivers here. Not a Google account. |
| **Domain registrar** | GoDaddy (`vamo.world`) | see External services table. |
| **Android upload keystore** | `vamo-upload-keystore.jks` — **local only**, gitignored | `CN=Tiziano Rocca, O=Vamo, L=Tallinn, C=EE`; upload-key SHA256 `B6:18:BD:12:49:70:51:F5:18:37:9A:1E:2F:8E:88:E8:73:4C:1C:5E:48:E0:5E:68:BD:50:66:59:E0:9F:BB:89`. **Back up keystore + password separately.** Play App Signing holds the real app-signing key (its SHA-256 — needed for `assetlinks.json` — is available post-upload, TBD). |

**Account-critical mail** (Google security/policy) goes to the Play **login**
(`troccadev@gmail.com`), not the public contact — keep that inbox monitored.
