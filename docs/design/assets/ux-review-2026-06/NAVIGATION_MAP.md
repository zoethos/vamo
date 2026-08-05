# Vamo — Navigation Map

_Information architecture for the app. Updated 2026-06-23 (redesign pass). Screens marked **★** are roadmap/AI features; everything else is built or in-build._

Visual map: `design/nav-map/Vamo-Navigation-Map.png`
Per-screen mockups + element names: `docs/UI_REFERENCE.html`
Redesign screenshots: `design/assets/ux-review-2026-06/`

---

## A · Global shell (5-slot bottom nav)

The app shell is a **5-slot bottom navigation** with a center **context-fab** (lime, context-aware):

```
Trips        Activity        ( + )        Expenses        Profile
 luggage      timeline    context-fab     receipt_long     person
```

| Tab | Role | Drills into |
|---|---|---|
| **Trips** | Home — list of trips (featured + upcoming/past) | a **Trip** (section B) |
| **Activity** | Cross-trip passive history (read-only, icon-as-verb rows, filters) | the relevant trip surface per row |
| **( + ) context-fab** | The app's primary create action. **Context-aware:** `+expense` on the Expenses tab, `+trip` elsewhere | New trip flow · Add expense sheet |
| **Expenses** | Cross-trip **money home** (aggregator): spend-led, per-trip rollups | a Trip's **Expenses** list |
| **Profile** | Account · preferences (units km/mi) · privacy | settings sections |

**Rule:** the global tabs are **aggregators that drill into a trip**, never parallel destinations. `lime` is reserved for the single primary action on a screen (context-fab, Save, Settle up, Propose expense, Share Wrapped, Draft with AI).

---

## New trip flow (from context-fab → `+trip`)

```
New trip
├─ Trip name ............ free text
├─ Destination .......... AI resolve (sparkle) → resolves place + backdrop  ★
├─ Dates ................ booking-style date scroller (single day / range; optional times)
├─ Travel (ADVANCED) .... multimodal legs: mode + window + reach (km·mi / hours)  ★ advanced, gated
└─ Plan ................. ✦ Draft with AI (rockstar)  ·  "I'll plan it myself" (manual, equal path)
        └─ AI proposes "stops" (Visit / break / transfer) → tick to keep / skip → fills the Plan
```
- **Manual is first-class**; AI is the headline accelerator (badged ★ Vamo AI), never forced.
- Resolved destination + AI plan reuse the **POI resolution** engine and the **date scroller** control.
- Screens: `16-new-trip.png`, `17-date-scroller.png`, `18-advanced-travel.png`.

---

## B · Inside a Trip (sections)

Opening a trip shows the **Trip Dashboard** (hero backdrop, participants, total-spent card, quick-actions, recent activity). The quick-action grid opens these **peer sections**:

```
Trip
├─ Plan ............ itinerary timeline (day-grouped, type-accented stops, POI thumbnails, distance pills, RSVP)
├─ Expenses ....... the expense LIST (spend-led summary, M3 rows, "Propose expense" lime FAB)
├─ Balances ....... who owes who (net-balance donut + settle list + "Settle up")
├─ Map ★ .......... journey replay (per-member trails, pins, day scrubber)   — Wave 3
├─ Members ........ roster + invite (link / QR / contacts)
└─ Memories ....... photos / notes
```

### Expenses vs Balances (the distinction)
- **Expenses** = the *list of costs* (what was spent). Leads with **spend** (total + your share), with a quiet link across to Balances. Add = **"Propose expense"** (consent model) on the lime context-fab.
- **Balances** = *who owes who* (net position). Leads with the **net-balance donut**; primary action **"Settle up"**.
- Both are per-trip sections; the **global Expenses tab** aggregates the per-trip Expenses lists.

### Plan ▸ Add to plan (from the Plan section)
```
Add to plan (type-first sheet)
├─ Visit ...... POI search → resolved places (tap to pick)  → swipe row = Place Info card ★
├─ Train ...... stations + times
├─ Flight ..... resolve by flight number → auto-fills route/times  ★
├─ Transfer ... mode chips (car/taxi/ferry/bus) + pick-up/drop-off
├─ Lodging .... find a stay + check-in/out
└─ Other ...... freeform
```
Each added item is a **stop** on the Plan timeline. Place types (Visit, Lodging) carry a POI thumbnail; a **right-to-left swipe** on a POI row opens the **Place Info card** (photo, rating, hours, about — fed by the POI data). Screens: `07/09-add-to-plan`, `11/12-flight`, `13-place-info-card`.

---

## Trip close (Wave 2/3)
```
Trip → Close report (deemed-acceptance settlement)  →  Trip Wrapped ★ (recap story, shareable)
```
- **Close report**: calm, financial — final balances + deemed-acceptance.
- **Trip Wrapped ★**: tap-to-advance recap (totals, distance, photos, superlatives), lime "Share your Wrapped" with watermark — the share-the-story payoff. Screen: `05-trip-wrapped.png`.

---

## C · Separate from Activity — Notifications
Notifications are **personal, actionable, read/unread** (invites, accept/object, settle confirmations). **Activity is a passive log** and never an action center — the two stay distinct so neither becomes a noisy dumping ground.

---

## The Trip Map ★ (where it sits & what feeds it)
- **Sits** inside a Trip as a section peer (Plan/Expenses/Balances/**Map**/Members/Memories).
- **Fed by:** Plan POIs · expense places · Memories photo spots.
- **Powers:** Trip Wrapped (distance, route, highlights).
- Wave 3. Screen: `04-trip-map.png`.

---

## Screen index → screenshot

| Area | Screen | Asset |
|---|---|---|
| Shell | Navigation + context-fab | `01-navigation-fab.png` |
| Trip | Add expense | `02-add-expense.png` |
| Trip | Balances (net donut) | `03-balances.png` |
| Trip ★ | Trip Map | `04-trip-map.png` |
| Trip ★ | Trip Wrapped | `05-trip-wrapped.png` |
| Shell | Profile | `06-profile.png` |
| Plan | Add to plan (type-first) | `07-add-to-plan.png` / `09-add-to-plan-refined.png` |
| Review | Across-the-app notes | `08-review-notes.png` |
| Plan | Plan timeline | `10-plan-view.png` |
| Plan | Add-to-plan types | `11-add-to-plan-types.png` |
| Plan ★ | Flight resolve | `12-flight-resolved.png` |
| Plan ★ | Place Info card | `13-place-info-card.png` |
| Shell | Activity (refactor) | `14-activity-refactor.png` |
| Trip | Expenses list (refactor) | `15-expenses-refactor.png` |
| New trip | New trip flow | `16-new-trip.png` |
| New trip | Date scroller control | `17-date-scroller.png` |
| New trip ★ | Advanced travel (multimodal) | `18-advanced-travel.png` |
