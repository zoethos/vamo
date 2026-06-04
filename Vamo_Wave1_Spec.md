# Vamo - Wave 1 Build Spec

**Scope:** SplitTrip (trip-framed bill splitting) + solo trip capture + branded snapshot share.
**Target:** ship in 1-3 weeks, solo founder, Flutter + Supabase.
**Companion file:** `vamo_wave1_schema.sql` (runnable Supabase schema + RLS).

---

## 1. In / out of scope

**In:** auth; trips (solo or group); members; invite link + join-a-trip; expenses with custom splits; multi-currency (snapshot FX); derived balances; minimal settle-up (mark + confirm, deep-link to payment apps); solo trip capture (notes/photos); branded snapshot share; private-by-default; basic push; core analytics events; offline-first.

**Out (later waves):** live location, ghost-trail, action-cam, recap video, branching replay, itinerary, events, Tally/Atlas/Orbit, live web "view-before-install".

---

## 2. Tech choices

- **Client:** Flutter (Dart). State: Riverpod. Local cache: Drift (SQLite). Image-from-widget: `screenshot` or `RenderRepaintBoundary` for the branded share card.
- **Backend:** Supabase - Postgres + Auth (email, Apple, Google, phone) + Storage (avatars, snapshot images) + Realtime + Edge Functions.
- **FX:** a free daily rates API (e.g. exchangerate.host), cached once/day; store the rate snapshot on each expense.
- **No Mapbox in Wave 1** - the snapshot is a styled card, not a live map.
- **Money:** integer cents everywhere. No floats. Vamo never moves money.

---

## 3. Data model

See `vamo_wave1_schema.sql`. Tables: `profiles, trips, trip_members, invites, expenses, expense_shares, settlements`. Derived `trip_balances` view. Everything is RLS-gated by trip membership via the `is_trip_member()` helper; joining a trip goes through the `join_trip(token)` security-definer function. A trip can have a single member (solo) - group features simply light up when others join.

**Invariant:** for each expense, `sum(expense_shares.share_cents) == expenses.base_cents`. Enforce in the app on write.

---

## 4. Settle-up algorithm (deterministic, no AI)

Goal: from net balances, produce the **minimum number of transactions** that clears the trip. Pure integer arithmetic.

```
// net_cents per member, in trip base currency (from trip_balances):
//   net > 0  => the group owes this member (creditor)
//   net < 0  => this member owes the group (debtor)

List<Settlement> settleUp(Map<UserId,int> net) {
  final creditors = net.entries.where((e) => e.value > 0)
      .map((e) => [e.key, e.value]).toList();        // [user, amount]
  final debtors   = net.entries.where((e) => e.value < 0)
      .map((e) => [e.key, -e.value]).toList();        // positive amounts
  creditors.sort((a,b) => b[1].compareTo(a[1]));      // largest first
  debtors.sort((a,b) => b[1].compareTo(a[1]));

  final out = <Settlement>[];
  int i = 0, j = 0;
  while (i < debtors.length && j < creditors.length) {
    final pay = min(debtors[i][1], creditors[j][1]);  // cents
    out.add(Settlement(from: debtors[i][0], to: creditors[j][0], cents: pay));
    debtors[i][1]   -= pay;
    creditors[j][1] -= pay;
    if (debtors[i][1] == 0) i++;
    if (creditors[j][1] == 0) j++;
  }
  return out;                                          // who pays whom, minimal
}
```

**Multi-currency:** when an expense is added in a non-base currency, fetch the day's rate, compute `base_cents = round(amount_cents * fx_rate)`, and store both the original (`amount_cents`,`currency`) and `base_cents`,`fx_rate`. All balances and settle-up run in trip base currency. (Penny-rounding residue of a cent or two is acceptable; assign any remainder to the largest share.)

**Unit-test this** with fixtures (it's deterministic and high-value): equal split, custom split, multi-payer, multi-currency, and a 3-person cycle.

---

## 5. Screens

| # | Screen | Purpose | Primary action | Notes / edge cases |
|---|--------|---------|----------------|--------------------|
| 1 | Auth / onboarding | sign in | continue with Apple/Google/email/phone | create profile row (trigger handles it) |
| 2 | Trips list | see your trips | "Si va?" (create trip) | empty state = the hook; solo + group trips together |
| 3 | Create trip | start a trip | create | choose solo or "invite friends"; name, destination, dates, base currency |
| 4 | Trip home | hub | add expense | tabs: Expenses / Balances / Members; **solo trips hide Balances** |
| 5 | Add expense | log a cost | save | amount + currency, payer, split (equal or custom), description, category, date |
| 6 | Balances / settle-up | who owes whom | "mark as settled" | runs settleUp(); deep-link to Venmo/PayPal/Wise prefilled; other party can confirm |
| 7 | Invite / join | grow the trip | share link | create invite token; link opens app (or store). Mid-trip join supported |
| 8 | Solo capture | log a solo trip | add note/photo | minimal: title, notes, photos; feeds the snapshot |
| 9 | Branded snapshot | shareable card | share | render a styled card (trip + totals + Vamo logo) to the share sheet |
| 10 | Settings | profile & prefs | edit | display name, base currency, billing placeholder |

---

## 6. Key flows

**Invite & join-a-trip.** Member taps Share -> client inserts an `invites` row -> shares `https://vamo.app/j/<token>` (deep link). Opener taps: if app installed, call `rpc('join_trip', { p_token })` which adds them as an active member and returns the trip id -> open the trip; if not installed, route to the app store with the token preserved. (The "view-before-install" web preview is a Wave 2+ nicety.)

**Settle-up.** On Balances, run `settleUp(net)` to show the minimal "X pays Y EUR Z" list. "Mark as settled" writes a `settlements` row (`status='marked'`), optimistic-updates balances, and deep-links to the chosen payment app with the amount prefilled where the app supports it. The recipient can later "confirm" (`status='confirmed'`). Vamo never touches the money.

**Branded snapshot share.** Compose a card widget (trip name, dates, total spent, member avatars, a tasteful teal/sand background, Vamo wordmark) -> rasterise to PNG -> system share sheet. This is the Wave-1 seed of the broadcast growth loop; fire `snapshot_shared`.

---

## 7. Offline-first

Drift mirrors `trips`, `trip_members`, `expenses`, `expense_shares` locally and is the UI source of truth. Writes are optimistic and queued; a sync worker reconciles to Supabase (last-write-wins per field). Subscribe to a Realtime channel per open trip so co-editors see live updates.

---

## 8. Non-functional

- **Privacy:** all trips `visibility='private'` by default; RLS enforced; verify with Supabase's RLS tester. Snapshot images in a private bucket, shared via signed URL only when the user chooses to.
- **Billing principle (carry from day one):** upgrade anytime, downgrade/cancel at end of cycle, no dark patterns. (Paid tiers arrive later; wire the entitlement check now.)
- **Analytics (the growth metrics):** PostHog events `trip_created, member_invited, invite_accepted, expense_added, settle_marked, settle_confirmed, snapshot_shared`. These are your North-Star loop instrumentation.
- **i18n:** externalise strings from the start.
- **Error presentation policy:** users never see raw exceptions. Every user-facing error message comes from a fixed, localized catalogue keyed by the `action_failure` classification (`network` / `server` / `auth` / `unknown`) — never `$e`, never an exception's `toString()`, never anything naming the framework, API, or a third-party service (no "Supabase", "PostgREST", "PGRST…", stack traces, or URLs). One helper (`showActionError`) is the single path: it fires `action_failed` telemetry AND shows the safe message, so neither can be forgotten. In debug builds only, the sanitized code (e.g. `PGRST202`) may be appended in parentheses; raw exception text goes exclusively to logs (and to crash reporting when Sentry lands). Catalogue messages are actionable and blame-free: network → "No connection — check your network and try again"; auth → "Your session expired — please sign in again"; server/unknown → "Something went wrong on our side — please try again in a moment."

---

## 8b. Product signals (the listening stack)

Four layers of signal, from "is the loop working?" down to "what do users want that we haven't built?". All flow through the existing `Analytics` seam (`PosthogAnalytics` / `DebugAnalytics`) except suggestions, which also persist to Supabase.

### Layer 1 — North-Star funnel (built)

The seven events in section 8. Business-loop health only.

### Layer 2 — UX friction

| Event | Fired when | Properties |
|-------|-----------|------------|
| `screen_viewed` | router navigation (go_router observer) | `screen` |
| `error_shown` | any `AppErrorState` renders | `screen`, `kind` (network/server/unknown) |
| `empty_state_shown` | any `AppEmptyState` renders | `screen` |
| `flow_abandoned` | a started flow's screen is disposed without save | `flow` (add_expense/create_trip/invite), `elapsed_ms` |
| `action_failed` | a user-initiated write fails (SnackBar-class errors incl. create trip, add expense, settle, suggest) | `screen`, `action`, `kind` (network/server/auth/unknown), `code` (sanitized, e.g. PostgREST `PGRST202` — never raw exception text) |

`flow_abandoned` is the valuable one: high abandonment on add-expense = the form is too heavy. Implement as a tiny `FlowTracker` started on screen entry, completed on save, fired on dispose-if-incomplete.

### Layer 3 — Intention doors (fake doors, max 3 in Wave 1)

| Event | Door | Where |
|-------|------|-------|
| `plus_interest_tapped` | the existing disabled **Vamo Plus** placeholder | Settings |
| `recap_interest_tapped` | "Trip recap video — coming soon" teaser | trip home, post-trip |
| `map_interest_tapped` | "Trip map — coming soon" teaser | trip home |

Rules: clearly labelled "coming soon" (no dark patterns), tap records the event and shows a friendly sheet with an optional one-tap "tell me when it's ready" (fires `notify_me_opted_in` with `feature` property). Never more than three doors at once; retire a door when its feature ships or interest is proven.

### Layer 4 — Suggest a feature (explicit demand)

A "Suggest a feature" entry in Settings: free-text (required, max 500 chars) + optional category chip (trips / money / sharing / other). Stored in the `suggestions` table (migration `0006_suggestions.sql`: insert-own + read-own RLS; no public board in Wave 1). Fires `suggestion_submitted` with `category` only — the text stays in Postgres, out of PostHog. Submitting shows a genuine thank-you state ("we read every one — really").

**Close the loop:** when a suggested feature ships, mention it in release notes ("you asked, we built it"). A suggestion box that visibly works builds loyalty; a black hole breeds churn.

**Reading the signals together:** layers 2 and 4 are biased opposite ways — suggestions overweight vocal power-users, friction events capture the silent majority who just leave. Decisions should triangulate: a wave-order change needs support from at least two layers.

---

## 9. Acceptance criteria (Wave-1 "done")

1. A **solo** user can create a trip, capture it (notes/photos), and share a branded snapshot.
2. A **group** can create a trip, invite via link, others join (including mid-trip), add expenses with custom splits in multiple currencies, see a correct **minimal** settle-up, and mark/confirm settlements.
3. All data is **private by default** and RLS-enforced (validated with the RLS tester; a non-member cannot read a trip).
4. Works **offline** and syncs on reconnect.
5. The settle-up engine and FX math pass unit tests (equal, custom, multi-payer, multi-currency, 3-person cycle).
6. All **analytics events** fire.
7. **Product signals** are live: screen/error/abandonment events fire, the three intention doors record taps, and a suggestion lands in the `suggestions` table with RLS verified (submitter can read their own; nobody else's).

---

## 10. Suggested build order

1. Supabase project + run `vamo_wave1_schema.sql`; wire auth + profile trigger.
2. Flutter monorepo: `app_core` (auth, supabase client, design system, Drift, analytics) + `feature_split`.
3. Trips list + create trip (solo + group).
4. Members + invite + `join_trip`.
5. Add expense + shares (equal/custom) + FX snapshot.
6. Balances view + settle-up engine (+ unit tests) + mark/confirm + payment deep-links.
7. Branded snapshot share.
8. Solo capture.
9. Offline cache + realtime sync.
10. Polish, empty states ("Si va?"), analytics QA, RLS QA, ship to TestFlight / Play internal.
