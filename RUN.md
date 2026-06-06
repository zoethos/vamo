# Running Vamo locally

## Slice 0 — walking skeleton

Sign in → land on an empty trips list. Proves Flutter, Supabase auth, profile trigger, RLS, and an authorized query.

## Slice 1 — create & see a solo trip

Create a trip → persists to Postgres and Drift → appears in the list → opens trip home. Kill the app and reopen — the trip is still there.

## Slice 2 — log an expense (equal split)

Add a cost in trip base currency → equal shares written → `sum(shares) == base_cents` enforced → listed on trip home. Fires `expense_added`.

## Slice 3 — balances & settle-up

Net balances from Drift (same formula as `trip_balances`) → minimal `settleUp()` → "who pays whom" on the Balances tab. Unit tests cover equal/custom/multi-payer/multi-currency/3-person cases.

## Slice 4 — settle & confirm

Payer taps **Mark as settled** → pick payment app (honest partial handoff; Venmo USD-only) → `marked` row optimistically nets balances. Recipient **Confirm** or **Reject**; payer can **Cancel** a marked payment. Fires `settle_marked` and `settle_confirmed`.

## Slice 9 — offline sync + realtime

Writes go to **Drift first**, then the **sync outbox**; [SyncWorker](packages/app_core/lib/src/sync/sync_worker.dart) pushes when online. Pull sync **prunes** trips/expenses removed on the server. **Connectivity** + sign-in trigger sync. Open trip home → **Realtime** subscription refreshes that trip.

## Slice 8 — solo capture

Solo trips get a **Capture** tab — notes + photos (downscaled on pick). Remote photos use **signed URLs** cached locally. Sign-out wipes `captures/` on disk. Storage RLS in `0005_captures_storage_policies.sql`.

## Slice 7 — branded snapshot share

Trip home → share icon → branded card (trip, dates, total spent, member avatars, Vamo wordmark) → **Share image** → PNG via system share sheet. Fires `snapshot_shared`. Optional upload to private `snapshots` bucket when configured.

## Slice 6 — multi-currency

Log an expense in a currency other than the trip base → client fetches daily FX (edge function or exchangerate.host fallback) → stores `amount_cents`, `currency`, `base_cents`, and `fx_rate` snapshot → balances and settle-up stay in trip base currency.

## Slice 5 — invite & join

**Invite Vamigos** on Members → share `https://vamo.world/j/<token>` (+ `app.vamo://join?token=…`) or **Show QR** (same web link — opens app via universal link / redirect page). Opener signs in → `join_trip` RPC → trip home. Fires `member_invited {channel: link|qr}`, `qr_shown` (when QR displayed), `invite_accepted {channel}`.

### Slice 15 — QR invite (R9)

1. Phone A: trip → **Members** → **Show QR** (full-screen sheet with brand header).
2. Phone B: scan with the **system camera** (or in-app **Scan a Vamo QR**) → `https://vamo.world/j/<token>` → app opens.
3. Phone B lands in the trip. PostHog: `invite_accepted` with `channel: qr` (no token in properties).
4. Link share still fires `member_invited` with `channel: link`. Web hides scan entry; invite links still work.

## Slice 16 — roles + push + scheduled jobs (R1, R2, Wave 2)

### Roles (migrations `0012_add_co_admin_value.sql` + `0013_trip_roles.sql`)

- `trip_members.role`: `owner` | `co-admin` | `member`
- **Co-admin** can edit trip content (name, dates, …) — same RLS as owner for `trips` update; cannot grant roles, transfer ownership, or (in S17) cancel/close.
- **Owner** → Members tab → ⋮ on a Vamigo → **Make co-admin** / **Remove co-admin** (`set_member_role` RPC).

```bash
supabase db push   # applies 0012, 0013, 0014 in sequence
dart run tool/rls_smoke.dart   # incl. co-admin update / role-grant denial cases
```

### Push (migration `0014`, T10.5)

1. **Firebase:** Android app **`app.vamo`** (matches `applicationId`) — `google-services.json` → `app/android/app/`.
2. **Supabase secrets:** set the full service-account JSON as one secret (minify to one line):

```bash
npx supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account","project_id":"...",...}'
```

   Firebase console → Project settings → Service accounts → **Generate new private key**.
3. **Deploy:** `npx supabase functions deploy send-push`
4. **Device test (Android, app backgrounded):**
   - Sign in → token registers via `register_push_device` RPC (`push_devices` table).
   - From a REST client or curl with your JWT:

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-push" \
  -H "Authorization: Bearer $USER_JWT" \
  -H "Content-Type: application/json" \
  -d '{"title":"Vamo","body":"Test push","route":"/trips/<trip-id>"}'
```

   - Tap notification → app opens on the trip route (same handler as deep links).

### Scheduled jobs (decision + proof)

See `docs/SCHEDULED_JOBS.md`. Check pg_cron in SQL editor; if unavailable, schedule Edge Function `scheduled-heartbeat` (hourly cron). Heartbeats land in `job_heartbeats`.

## Slice 17 — trip lifecycle (R3, Wave 2)

Contract: `docs/workflows/trip-closure.md` (deemed acceptance, 14-day window).

```bash
supabase db push   # applies 0015_trip_lifecycle.sql
npx supabase secrets set CRON_SECRET='…'
npx supabase functions deploy trip-lifecycle-jobs --no-verify-jwt
dart run tool/rls_smoke.dart   # incl. write-after-close + deemed-close cases (needs RLS_SERVICE_ROLE_KEY)
melos run ci
```

**Demo:** create trip → **Request close** (owner) or all members **I'm done** →
members **Accept close** / **Object…** → after 14 days (or service-role job in
smoke) trip `closed` → add expense blocked, settlement still allowed → owner
**Close anyway** only when an objection is open.

Lifecycle RPCs: `request_trip_close`, `mark_trip_member_complete`, `accept_trip_close`,
`object_to_trip_close`, `withdraw_close_objection`, `force_close_trip`, `cancel_trip`.

## Slice 17.1 — lifecycle UX fix (phase-aware + quiet)

Spec: `docs/slices/S17_1_PROMPT.md` · UI only (no schema/RPC change).

Active trips no longer show a lifecycle button wall. **Pre-start** owner gets
**Cancel trip** in the app-bar overflow only — not "I'm done" or "Request close".
**Ongoing** owner/member get **I'm done** (and owner **Request close**) in overflow;
cancel is hidden. **Closing** keeps the prominent Accept / Object banner.

```bash
melos run ci   # widget tests assert phase gating + overflow placement
```

## Slice 18 — TripBoard plan items (R4, Wave 2)

Spec: `docs/slices/S18_PROMPT.md` · depends on S17 (`is_trip_writable`).

```bash
supabase db push   # applies 0016_trip_plan_items.sql
dart run tool/rls_smoke.dart   # plan insert + closed-trip write block + checklist check
melos run ci
```

**Demo:** open trip → **Plan** tab → add lodging + flight with dates → reorder →
checklist **Packing: sunscreen** → second device sees sync → close trip → board
read-only (add/edit/delete disabled).

## Slice 19 — money governance I (R5, Wave 2)

Contract: `docs/workflows/expense-consent.md` · constitution D1 + A1 (dispute after close; settlement-confirm gate deferred to S22).

```bash
supabase db push   # applies 0017 + 0018 (share guard + dispute sync touch)
dart run tool/rls_smoke.dart   # propose/commit net + dispute-on-closed + forged-insert guard
melos run ci
```

**Demo:** owner taps **Propose a cost** (admin-only, online RPC) → ghost row appears → **commits** → balances update → member **disputes** own share (net unchanged, flag visible on all devices) → close trip → dispute still allowed → cancelled trip blocks dispute.

Born-committed logging still uses **Add expense** (offline-first outbox). Governance RPCs (`propose_expense`, `commit_expense`, `void_expense`, `respond_to_share`) require connectivity — no outbox queue.

## Slice 20 — money governance II (R6, Wave 2)

Contract: `docs/design/MONEY_GOVERNANCE.md` D3 + D4 + A3 · workflow note: `docs/workflows/budget-fx.md`

```bash
supabase db push   # applies 0019_budget_and_fx.sql
dart run tool/rls_smoke.dart   # budget/FX role gates + forward-only FX + over-budget commit
melos run ci
```

**Demo:** trip settings → set formal budget → capture USD rate (market, read-only) → refresh rate → existing expense `fx_rate` unchanged → propose over-budget cost → typed confirm on commit → DB still accepts.

Trusted capture: client sends **trip + currency only** — never a rate number. Refresh is forward-only (D4).

### vamo.world site (`web/apps/site`)

Public Next.js on Vercel: landing, `/privacy`, `/terms`, `/j/[token]` redirect, `/.well-known/assetlinks.json`.

### 1. Backend

```bash
supabase start                 # local stack, or use a cloud project
supabase db push               # applies migrations (incl. 0002_create_trip_rpc.sql)
```

In the Supabase dashboard (or `config.toml` for local), enable **email auth**. Apple/Google need provider config before those buttons work.

### 2. Client config

```bash
cp .env.example app/.env
# edit app/.env with SUPABASE_URL and SUPABASE_ANON_KEY
```

The `.env` is a Flutter asset (`app/pubspec.yaml`) and is gitignored.

### 3. Drift codegen (required before analyze/test)

```bash
melos bootstrap
melos run build_runner    # or: melos run ci  (codegen → analyze → test)
```

The checked-in `app_database.g.dart` is a review stub only — `melos run analyze` fails on it until build_runner regenerates.

### 4. Run

**Monorepo layout:** the Flutter app lives in `app/`. Melos workspace root is `Vamo/` (where `melos.yaml` lives).

| Do | Directory |
|----|-----------|
| `melos bootstrap`, `melos run build_runner`, `melos run test` | `Z:\vamo\Vamo` |
| `flutter create .` (platform folders **only**) | `Z:\vamo\Vamo\app` |
| `flutter run` | `Z:\vamo\Vamo\app` |

Never run `flutter create .` at the monorepo root — it does not add Android under `app/` and can litter the workspace with root `.dart_tool` / lockfiles.

```bash
dart pub global activate melos   # once
cd Z:\vamo\Vamo
melos bootstrap
melos run build_runner
cd app
flutter run
```

**Chrome / web (dev harness):**

```bash
cd app
flutter run -d chrome --web-port 3000
```

Use a second browser account for invite/join and co-edit QA. Snapshot share is device-only for now: the share/save path touches `dart:io` at runtime and will throw on web. Chrome is a test harness for auth/trips/expenses/join, not for sharing.

### 5. Slice 0 demo

1. Auth screen → email OTP → verify → **Your trips** (empty).
2. Sign out works from the app bar.

### 6. Slice 2 demo

1. Open a trip → **Add expense** → e.g. €30, description "Dinner" → **Save**.
2. Expense appears on the Expenses tab with formatted amount.
3. Debug log: `[analytics] expense_added`.
4. With 3 members (after Slice 5), €30 splits 1000¢ each; solo trips assign the full amount to you.

Run unit tests: `cd packages/feature_split && flutter test` (expense split + settle-up).

### 7. Slice 3 demo

1. Trip with **2+ members** and at least one expense → open **Balances** tab.
2. See minimal "X pays Y" lines (e.g. two payments after a €30 dinner split 3 ways).
3. Solo trips still hide the Balances tab.

### 8. Slice 4 demo

1. As the **payer** on a settle line → **Mark as settled** → Venmo (or PayPal/Wise).
2. Payment app opens with amount prefilled where supported; line drops off after mark (balances update).
3. As the **recipient** → **Confirm** on the pending card at the top of Balances.
4. Debug: `[analytics] settle_marked` then `settle_confirmed`.

### 9. Slice 9 demo

1. `supabase db push` (incl. `0004_realtime_publication.sql`).
2. Device A: add expense offline (airplane mode) → appears in list.
3. Reconnect → expense syncs; Device B on same trip sees it live (open trip home).
4. Delete a trip on server → pull sync removes it locally after refresh.

### 10. Slice 8 demo

1. Solo trip → **Capture** tab → **Add note** + **Add photo**.
2. Share snapshot — card shows photo strip and note highlight.
3. `supabase db push` (`0003_trip_capture.sql`, `0005_captures_storage_policies.sql`).
4. iOS: `NSPhotoLibraryUsageDescription` in Info.plist — see `app/README_PLATFORM.md`.
5. Second device: after sync, photos download via signed URL into app documents.

### 11. Slice 7 demo

1. Open a trip with at least one expense.
2. Tap the **share** icon in the app bar → preview the card.
3. **Share image** → pick Messages / Instagram / save to photos.
4. Complete a share (not cancel) → debug: `[analytics] snapshot_shared`.

Regenerate card golden: `cd packages/feature_split && flutter test --update-goldens test/snapshot_card_golden_test.dart`

### 12. Slice 6 demo

1. Create a trip with base **EUR**.
2. **Add expense** → **Spent in: USD** → e.g. $50 → preview shows ≈ EUR equivalent.
3. Save → list shows **€X** with **($50)** underneath.
4. **Balances** use the converted base cents (same as a native EUR expense).

FX setup (required for foreign expenses):
1. Free key at https://exchangerate.host → `EXCHANGERATE_ACCESS_KEY` in `app/.env`
2. Optional: `supabase secrets set EXCHANGERATE_ACCESS_KEY=...` then `supabase functions deploy fx-rates`
3. Set `FX_RATES_FUNCTION_URL` in `app/.env` to use the edge proxy

After one online fetch, foreign expenses work offline using the last cached rate (marked stale in the UI).

### 13. Slice 5 demo

1. Trip → **Members** → **Invite Vamigos** → share link (AirDrop / copy).
2. Second account (or device) opens link → sign in if needed → lands on trip.
3. Balances tab appears once 2+ members; add expenses and settle.
4. Debug: `member_invited`, `invite_accepted`.

**Deep links:** configure `app.vamo` + `https://vamo.world/j/*` in platform manifests when you `flutter create` the app project (see `app/README_DEEP_LINKS.md`).

### 14. Slice 1 demo

1. Tap **Si va?** → fill trip name → **Create trip**.
2. Land on trip home (Expenses tab; Balances hidden for solo).
3. Back to list — trip appears.
4. Force-quit the app → reopen → trip still in the list (Drift + remote).
5. Debug console shows `[analytics] trip_created`.

### 15. Slice 14 demo

1. `supabase db push` (incl. `0008_expense_receipts.sql`).
2. **Add expense** → **Scan receipt** → camera or gallery → attach optional photo.
3. Save (manual fields unchanged) → expense list shows receipt thumbnail.
4. Tap thumbnail → full-screen viewer (signed URL after sync, local file offline).
5. Debug: `[analytics] expense_added` with `has_receipt: true`; failed upload → `action_failed` (`attach_receipt`) but expense still saves.

### 16. Tests

```bash
melos run test
```

`app/test/smoke_test.dart` covers the auth-redirect rule.

**i18n maintenance**

```bash
# Pseudo-locale ARB (en_XA) from English template
dart run tool/gen_pseudo_arb.dart
cd app && flutter gen-l10n

# RTL + snapshot theme goldens (Noto fonts loaded via flutter_test_config.dart)
cd packages/feature_split && flutter test --update-goldens test/i18n_rtl_golden_test.dart test/snapshot_card_golden_test.dart
```

## Slice 10 — settings, polish, analytics, ship prep

**Settings** (trips list → gear): edit display name and default trip currency (`profiles` table). Billing shows a **Vamo Plus** placeholder (Wave 2+). Sign out clears local Drift + capture cache.

**PostHog:** set `POSTHOG_API_KEY` in `app/.env`. Without it, events print to the debug console. On sign-in the SDK calls `identify(userId)`.

### 17. Slice 10 demo

1. Trips list → **Settings** → change display name → **Save**.
2. Create trip — base currency defaults to your profile currency.
3. Run each North-Star flow once; confirm events in PostHog Live (or debug logs):
   `trip_created`, `member_invited`, `invite_accepted`, `expense_added`,
   `settle_marked`, `settle_confirmed`, `snapshot_shared`.
4. Unit lock: `packages/app_core/test/analytics_events_test.dart`.

**RLS QA:** [docs/RLS_QA.md](docs/RLS_QA.md)

**TestFlight / Play internal:** [docs/SHIP_INTERNAL.md](docs/SHIP_INTERNAL.md)

## Slice 11 — product signals (milestone Signals, T11.1–T11.6)

Spec **§8b** / acceptance **AC7** — four layers on top of the North-Star funnel. Backlog: `Vamo_Wave1_Backlog.xlsx`. Cloud migrations `0001`–`0006` are already applied on project `mjercplkmuoctdklosyy`; baseline the CLI with `supabase link --project-ref mjercplkmuoctdklosyy` then `supabase migration repair` so future `db push` does not replay history.

| Layer | What |
|-------|------|
| 2 — Friction | `screen_viewed` (named routes), `error_shown` / `empty_state_shown` (`AppErrorState` / `AppEmptyState`), `flow_abandoned` (`create_trip`, `add_expense`, `invite` on button tap), `action_failed` (write failures via SnackBar — sanitized `code`, never raw exception text) |
| 3 — Intention doors | Vamo Plus (Settings), trip map + recap teasers (trip home); `notify_me_opted_in` (PostHog only — no persisted opt-in list yet) |
| 4 — Suggestions | Settings → **Suggest a feature** → Postgres `suggestions`; `suggestion_submitted` (category only); `app_version` from `package_info_plus` |

### 17. Slice 11 demo (T11.1–T11.5)

1. `supabase link` + `migration repair` if the CLI is not yet baselined (migrations already live on cloud).
2. Navigate trips → trip home → settings; confirm `screen_viewed` in debug/PostHog.
3. Open **Vamo Plus** and **Trip map** teasers → interest + optional notify-me events.
4. Settings → **Suggest a feature** → submit → row in `suggestions` (dashboard / SQL); thank-you screen.
5. Start **Add expense**, back out without saving → `flow_abandoned` with `flow: add_expense`.
6. Tap **Invite Vamigos** and complete share → no `flow_abandoned` for `invite`; open Members without inviting → no invite abandonment.

### 18. T11.6 — Signals QA (keep open until verified)

- [ ] **PostHog Activity:** every named route appears as `screen_viewed` with matching `screen` (`trips`, `trip_home`, `settings`, `create_trip`, `add_expense`, `suggest_feature`, …).
- [ ] Trigger a sync error on trips list → `error_shown` with `screen: trips_list` and `kind: network` (or appropriate kind).
- [ ] North-Star + product-signal events present after the §17 demo flows.
- [ ] **Cloud RLS:** suggestions insert/read-own per [docs/RLS_QA.md](docs/RLS_QA.md).

## Slice 12 — snapshot themes (milestone Themes, T12.1–T12.3)

First Wave 2 seed, tracked in the Wave-1 backlog: keyword-matched theme packs on the share card, **free for everyone**. No backend migration.

| Task | What |
|------|------|
| T12.1 | Theme packs + `SnapshotThemes.resolve(destination, tripName)` |
| T12.2 | `SnapshotBrandedCard` renders pack gradient, stat panel, accent, tagline |
| T12.3 | Share preview chip, `theme_id` on `snapshot_shared`, resolver + golden tests |

Built-in packs: **default** (teal/sand), **rome**, **coast**, **paris**. First keyword hit wins (pack order in `snapshot_themes.dart`).

### 19. Slice 12 demo (T12.1–T12.3)

1. Create or open a trip with destination **Rome** (or name containing `Roma` / `Colosseum`).
2. Trip home → **Share snapshot** → preview shows **Rome theme** chip and terracotta card.
3. Share → PostHog `snapshot_shared` includes `theme_id: rome`.
4. Repeat with a non-matching destination → **Vamo** default theme.
5. `melos run test` — `snapshot_theme_resolver_test.dart` + Rome golden (update goldens locally if first run: `flutter test --update-goldens` in `packages/feature_split`).
