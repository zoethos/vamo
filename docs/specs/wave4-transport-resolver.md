# Wave 4 — Transport Resolver (schedule resolution → trip plan)

**One line.** A new view that resolves real **train / bus / plane schedules** for a leg and inserts the
chosen option into the trip plan as a **Transfer** item — starting on the cheapest solid data sources and
scaling up to authoritative providers, **gated by the user's price tier**.

**Provider reference:** [`wave4-transport-resolver-providers.xlsx`](wave4-transport-resolver-providers.xlsx)
(Providers · Vamo tier map · Rollout).

---

## Why this is cheap for us to build
It is the **second consumer of the premium-services control plane** (POI/Foursquare was the first — see
[`premium-services-control-plane.md`](premium-services-control-plane.md)) and it reuses the **existing
Transfer plan-item** end to end. We add a `transport` service key and one edge function; almost everything
else already exists:

| Need | Already in the app | Reused as-is |
|---|---|---|
| Gateway · cache · per-user meter · free-tier routing · upsell | control plane (`provider_config` / `service_usage` / `entitlements` / `service_usage_reservations`) | add `transport` to the `poi`/`weather`/`fx`/`llm` set |
| Server-side provider calls, secrets, normalized model | `poi-discovery` edge function pattern | clone into `transport-resolve` |
| The thing we insert | `PlanItemKind.transfer` + `TransferMetadata` (`subtype` train/flight/transit/drive/carRental, `origin`, `destination`, `provider`, `reference`) | prefill from the picked option |
| Origin / destination entry | places search + geocode | input fields |
| Keeping inserted dates legal | trip date-bounds trigger + `TripPlanDateBounds` (date-cleanup branch) | depart/arrive land inside trip range automatically |
| Where the leg shows up | Plan timeline + **Trip Map** (transfers become route legs) + Trip Wrapped | no extra work |

---

## Scope
**Schedule resolution only** — timetables and routes. **Not** booking, **not** PNR/ticketing, **not** live
seat/price. Read-only lookup → user picks → insert as a Transfer plan item. (Booking is a later, separate
wave with its own commercial/legal surface.)

---

## A. The view (UX)
**Entry points**
- From **Add-to-Plan → Transfer** (the existing type-first tile) → "Find a connection", **or**
- A dedicated **"Find transport"** action on the Plan tab.

**Inputs**
- **Origin** + **Destination** — place search (reuse the places/geocode path; airports resolve via the
  OpenFlights reference for air mode).
- **Date** — constrained to the trip via `TripPlanDateBounds` (same bounds the plan sheet already enforces).
- **Mode** — Train / Bus / Plane (maps to `TransferSubtype`).

**Results**
- A ranked list of candidate connections: depart → arrive, operator, duration, # changes.
- **More than one match → the user picks** (single-select list; this is the "if more than one we allow
  picking" requirement).
- Empty / gated states: no result → manual-entry fallback (the current Transfer form); over-quota → upsell.

**Action**
- Select → prefilled `TransferMetadata` (`subtype`, `origin`, `destination`, `provider`, `reference` =
  service/flight number, plus additive `departAt` / `arriveAt` / `operator`) → insert via the existing
  `addPlanItem`. Times respect trip bounds by construction.

---

## B. Control-plane reuse (the convenient core)
Add **`transport`** as a service in the existing tables — no new infra:
- **`provider_config`** rows per provider: `routing_order[]` (per mode/region), `monthly_free_cap`,
  `enabled`, `default_free_quota`, policy flags. Admin-switchable without an app release.
- **`service_usage`** counters: per-provider monthly global + per-user monthly, `service = 'transport'`.
- **`entitlements.plan`** (`free` | `plus`, with a future `pro`) selects the provider ladder.
- **`service_usage_reservations`**: the edge fn **reserves** capacity before a fresh provider call, then
  marks `completed` / `failed`.

**Edge function `transport-resolve`** (mirrors `poi-discovery`):
- Input `{ trip_id, mode, origin, destination, date, session_id }`.
- Mode + tier → pick provider via `routing_order`; **reserve → call adapter → normalize → complete/release**.
- **Per-session metering** (idempotency by `session_id`, not per keystroke), result **cache**, and
  `{ gated: true, upsell: 'transport' }` on quota exhaustion.
- Provider adapters behind one normalized model:

```text
TransportOption {
  mode,            # train | bus | plane
  operator,        # e.g. "Trenitalia", "Lufthansa LH"
  serviceRef,      # train number / flight number  -> TransferMetadata.reference
  origin, destination,
  departAt, arriveAt,
  legs[],          # changes, for display
  source           # which provider answered (telemetry)
}
```

Per the control-plane rule: **always wrap, never call providers from the client** — keeps keys server-side,
makes provider swaps a config change, and lets caching/metering protect the free tiers.

---

## C. Provider ladder by price tier (cheapest-solid → authoritative)
Full detail in the Excel; summary:

- **Free** — Ground: **Navitia** *or* **Transitland** (open GTFS, EU+US). Air: **AeroDataBox** with a low
  monthly cap (we absorb ~$5/mo) + **OpenFlights** for airport/route reference. Raw GTFS (Mobility DB /
  gtfs.de / SNCF) as operator-gap fill.
- **Plus** — Ground: Navitia full + **Distribusion** (Italy rail, ferries). Air: AeroDataBox full /
  **Aviationstack**.
- **Pro (future / enterprise)** — Air: **OAG** / **Cirium** authoritative schedules; Distribusion full.

The control plane already does **multi-provider free-tier routing** and **upsell-on-limit**, so "splat the
feature across price levels" = `routing_order` + `entitlements`, not bespoke code.

---

## D. Data model
- **Reuse** `PlanItemKind.transfer` and `TransferMetadata` (already merged). The picked option fills
  `subtype` / `origin` / `destination` / `provider` / `reference`.
- **Additive** optional metadata keys `depart_at` / `arrive_at` / `operator` — S49 object-preserving
  encode/parse, so older clients ignore them safely.
- No new plan-item kind, **no migration to the plan schema**. Only the `transport` config/usage rows
  (control-plane tables that already exist).

---

## E. Phasing (build cheapest-first)
1. **Phase 1 (MVP, Free tier).** One ground provider (Navitia, EU+US) + AeroDataBox for air; the
   `transport-resolve` edge fn + normalized model + metering; resolve → pick → insert-as-Transfer. The
   whole loop, single-provider.
2. **Phase 2 (coverage + cache).** Raw-GTFS gap adapters (Mobility DB / gtfs.de / SNCF) + Aviationstack;
   server-side schedule cache; `routing_order` per region/mode.
3. **Phase 3 (premium + gating).** Distribusion (Italy/ferry), OAG/Cirium authoritative air; entitlement
   gating + upsell; admin provider switch; resolve the **`pro` tier** open decision.

---

## F. Guardrails
- **Resolution only**, never booking/PNR in this wave.
- **Licenses / ToS / attribution** per provider (GTFS feed licenses, AeroDataBox terms, Distribusion B2B
  terms). ViaggiaTreno is unofficial — best-effort, isolated behind its adapter, never a hard dependency.
- **Respect free tiers** via cache + per-user metering + global caps (same discipline as POI/Foursquare).
- **No keys in the client**; all provider calls server-side.
- **OpenSky is out of scope** (live ADS-B positions, not schedules).

---

## G. Tests
- **Pure:** provider-JSON → `TransportOption` normalizer (one fixture per provider); tier → provider
  selection from `routing_order` + `entitlements`; `TransferMetadata` prefill round-trip (incl. additive
  keys).
- **Widget:** results list renders + single-pick; empty → manual fallback; gated → upsell.
- **Smoke:** mock provider in tests (never hit real schedule APIs in CI — same lesson as Foursquare).

---

## Dependencies
- Premium-services control plane — **merged** (POI was first consumer).
- Transfer plan-item kind + metadata — **merged**.
- Places search / geocode — **merged**.
- Trip date-bounds (`TripPlanDateBounds` + trigger) — on `fix/add-plan-poi-date-cleanup`.

## Open decisions
1. **`pro` tier** — do we add a third `entitlements.plan` for enterprise air (OAG/Cirium), or keep
   `free`/`plus` and gate the premium providers inside `plus`?
2. **Free-tier air cost** — absorb AeroDataBox's ~$5/mo as a loss-leader for Free, or restrict Free to
   ground + OpenFlights reference (no live air times) and make live air a `plus` unlock?
3. **Ground default** — Navitia vs Transitland as the Phase-1 primary (both free; Navitia gives journey
   planning out of the box, Transitland is closer to raw GTFS).
