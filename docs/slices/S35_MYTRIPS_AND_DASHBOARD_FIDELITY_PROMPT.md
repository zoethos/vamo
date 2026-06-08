# S35 — My Trips list + Trip dashboard, high-fidelity light rebuild

**Branch:** `feature/mytrips-dashboard-fidelity` from `main` · **Est:** ~4–5 dev-days (phase it)
**Reads:** `docs/brand/Vamo-Light-Theme.png` + the founder's element spec (this doc).
**Why:** the generic cards/dashboard don't match the light reference. This slice builds
the two reference screens **exactly**, element by element, on S29 tokens. It is a
*fidelity* rebuild — match the mockup, don't approximate.
**Supersedes** the trip-card gradient treatment and the Phase-1 dashboard scaffold's
visual layer (keeps its data wiring).

## 0. Dependencies — read first (3 real gaps, not styling)
1. **Destination photos** (featured card bg + dashboard hero bg). No image source
   exists; `trip_card.dart` uses only `SnapshotThemes` gradient. The photographic
   look **requires `vamo_postcard`** (venue photo → static map → gradient fallback,
   `docs/POSTCARD_SPEC.md`). **Decision (founder):** build Postcard's photo
   resolution as part of S35, OR ship S35 on the gradient fallback first and swap to
   photos when Postcard lands. The reference's appeal is the photography — recommend
   building Postcard's resolver here.
2. **Category catalog `{label, icon, color}`** — `expenses.category` exists but is
   **free-text with no color/icon**. Define a canonical catalog (e.g. Food→orange
   fork-knife, Lodging→teal bed, Transport→blue car, Activities→coral, Shopping→
   mango, Other→graphite) + deterministic color for unknown free-text. **This single
   map drives BOTH the donut slices AND the recent-activity row icons.** Build it
   once in `app_core` (or `feature_split/expenses`), reuse in both places.
3. **Acceptance/completion bar** (featured card) — no clean "accepted vs expected"
   metric today (`status='active'`=joined; `closeAcceptedAt` is S22 close-accept).
   **Decide:** what does "accepted" mean for an upcoming trip (joined ÷ invited?
   confirmed ÷ members?) and where the denominator comes from. If there's no honest
   denominator yet, **omit the bar** rather than fake it (your point 7 already says
   upcoming cards have no bar — so the bar is featured-card-only and optional).

## 1. Screen A — "My Trips" list (replaces flat trip list)
Current `trips_list_screen.dart` is a flat `ListView.separated` of identical
`TripCard`s. Rebuild into a **focus hierarchy**:

| # | Element | Build | Data | Status |
|---|---------|-------|------|--------|
| 1 | **Featured = the next trip**, rendered LARGER | new `FeaturedTripCard` | first upcoming trip (soonest future `start_date`) | next-trip select = build |
| 2 | All other trips **smaller** (not in focus) | `CompactTripCard` list under an "Upcoming" header | remaining trips | build |
| 3 | Featured card has **full-bleed destination photo** bg | `Postcard` backdrop behind the card | dep #0.1 | needs Postcard |
| 4 | Bottom-left **overlay bar** with trip name (larger font) | gradient-scrim + `type.headline` over photo | `trip.name` | build (scrim for legibility) |
| 5 | Below title: **dates + participant count**, smaller, justified under title L→R | `formatTripDateRange` + member count | dates exist; members count exists | exists |
| 6 | Below dates: **completion/acceptance bar** (how many accepted) | thin progress bar | dep #0.3 | needs metric (else omit) |
| 7 | **Upcoming** compact cards: small location **thumbnail anchored left**, name, below smaller dates + participants, **NO acceptance bar** | `CompactTripCard` (leading thumbnail) | thumbnail = Postcard small; rest exists | thumbnail needs Postcall; layout build |
| 8 | **Top-right: notification bell + "+"** | app-bar actions | bell → notifications (W3 stub ok); + → create trip | build (+ exists; bell may stub) |

Notes: featured-vs-compact split = sort trips by upcoming `start_date`; the soonest
future trip is featured, the rest list under "Upcoming". Past/Drafts honor the
existing filter chips.

## 2. Screen B — Trip dashboard (when a trip is opened)
The Phase-1 `trip_dashboard_tab.dart` has the data wiring; this rebuilds its visual
layer to the reference, top to bottom:

| # | Element | Build | Data | Status |
|---|---------|-------|------|--------|
| 1 | **Top half = location photo** bg, big title "Amalfi Coast" + dates below (smaller) | `Postcard` hero (replaces `TripHeroHeader` gradient) | name+dates exist; photo = dep #0.1 | needs Postcard |
| 2 | **Member faces** in circular avatars in a row; trailing **"+"** to add contact/friend | `MemberAvatarRow` + add tile (reuse `trip_icon_action_tile`/invite flow) | members exist; add = invite flow | build |
| 3 | **Total Spent badge** (rounded square): "Total Spent" small gray; bold large €total; "Per person €311.40" small gray on left; **donut by category color** on right | `TotalSpentCard` + `CategoryDonut` (CustomPaint, zero-dep) | total+per-person exist; **donut needs category catalog #0.2** | partial — donut needs #0.2 |
| 4 | **4 square rounded buttons** L→R: Expenses · Plans · Balances · Members | the Phase-1 `_QuickActionsGrid` restyled to square tiles | exists | restyle |
| 5 | **Recent activity** badge: square, left icon (category color, e.g. orange fork-knife for a meal), description, right-end €amount, below it right-aligned relative time ("Today"/"Yesterday"/"2 days ago"/date) | `ActivityRow` | **activity feed exists** (`activity_repository.dart`); icon/color = catalog #0.2; relative time = new util | build (data exists) |

## 3. Shared pieces to build once
- **`CategoryCatalog`** (`{label, icon, color}`) — single source for donut slices +
  activity icons (#0.2). Put in `app_core` so both screens + future Tally reuse it.
- **`CategoryDonut`** — CustomPaint ring, slices = category share of trip total,
  colored from the catalog. Zero-dep (no fl_chart for one widget).
- **Relative-time formatter** — Today / Yesterday / N days ago / date.
- **`Postcard` resolver** (if dep #0.1 = build now) — featured card, compact
  thumbnail, and hero all consume it.

## 4. Verification
- `melos run ci` green.
- **Goldens** light + dark + small + RTL for: My Trips (featured + compact), the
  dashboard (hero, total+donut, quick-actions, activity row).
- Donut: unit test slice math (shares sum to total; empty/one-category cases).
- A11y: scrim contrast for text over photos (no unreadable title on a bright photo);
  no lime-on-light / teal-text-on-light.
- **On-device pass** (S25 Ultra): My Trips shows one large featured + smaller
  upcoming; dashboard hero photo, member avatars + add, total+donut by category,
  4 quick-actions, recent-activity row with relative time. Light + dark.

## 5. Phasing
- **Phase 1:** My Trips list hierarchy (featured + compact) + dashboard layout
  (hero, total+donut, quick-actions, activity) on the **gradient fallback** +
  the CategoryCatalog + donut + activity row. Ships the *structure & beauty* using
  data that exists. (Acceptance bar omitted unless #0.3 resolved.)
- **Phase 2:** swap gradient → **Postcard** destination photos (featured card,
  compact thumbnail, hero) once Postcard's resolver lands.
This way the layout fidelity ships first; photos drop in without layout change.

## 6. Reviewer checklist
- [ ] My Trips: one larger featured (next trip) + smaller compact upcoming list
- [ ] Featured: full-bleed visual + scrimmed title + dates/participants; (accept bar or omitted)
- [ ] Compact: left thumbnail + name + dates/participants, no accept bar
- [ ] App bar: notification bell + "+"
- [ ] Dashboard: photo/gradient hero + title + dates
- [ ] Member avatar row + add-member tile
- [ ] Total Spent card: total + per-person + category donut (colors from catalog)
- [ ] 4 square quick-action tiles (Expenses/Plans/Balances/Members)
- [ ] Recent activity row: category icon+color, description, amount, relative time
- [ ] CategoryCatalog drives BOTH donut + activity icons (one source)
- [ ] Postcard photos (Phase 2) or documented gradient fallback (Phase 1)
- [ ] Goldens (light+dark+small+RTL) + donut unit + a11y + device pass

## Notes
- Keep the current Vamo logo (not the mockup's mark).
- The donut/category color scheme is reused later by Tally/Wrapped (W3) — building
  the catalog now is the irreplaceable-data-adjacent groundwork.
