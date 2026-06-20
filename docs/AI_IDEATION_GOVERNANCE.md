# AI ideation governance

Effective 2026-06-05. AI agents working on Vamo (planning assistant, coding
agents, review bots) have a standing duty to be **propositive**: proactively
derive feature and improvement proposals from the current plan, the codebase,
the data model, and live telemetry — not only to execute instructions.

## The duty

- When working on any task, an agent that notices an adjacent opportunity
  (unused data, a cheap schema addition with later payoff, a synergy between
  features, a telemetry insight) MUST surface it — briefly, at the end of the
  work, never derailing the task itself.
- Proposals are tagged **[AI-IDEA]** and land in the **idea ledger**
  (the roadmap's "Extras" section, or this doc's ledger below for small ones).

## Triage rules (what made Slice 14 a yes)

A proposal ships out-of-wave ONLY if all three hold:
1. **Irreplaceable data**: waiting loses data that cannot be recreated later
   (e.g. geo-tags on receipts never scanned).
2. **Slice-sized**: ≤1 dev-day, rides existing plumbing, no new services.
3. **No gate-jumping**: it does not build what a future wave's go/kill gate
   might cancel.

Everything else — however good — goes to the ledger and waits for its wave's
planning. The founder decides; agents propose. Scope creep through charm is
the failure mode this document exists to prevent.

## Sources agents should mine

- **Schema**: columns/tables collected but not yet surfaced to users.
- **Telemetry**: funnel drop-offs, intention-door taps, suggestion themes.
- **Code**: built capabilities used in one place that generalize (e.g. the
  capture/storage pipeline, the theme cache, settle-up engine).
- **Docs/plan**: stated strategy not yet reflected in backlog items.
- **Session conversation**: founder ideas that imply siblings.

## Memo of lessons

- **Opaque credentials never enter analytics properties** — invite tokens briefly
  leaked into PostHog `member_invited` before R9 review; fixed by removal, not
  rotation (zero testers). Had this shipped broadly, the play would be bulk-revoking
  invites in the affected window.

## Ledger

| Date | Idea | Source | Triage |
|------|------|--------|--------|
| 2026-06-05 | Receipt→stop pipeline (EXIF geo on expenses now; stops in W3; own-photo place matching W3-4) | founder + elaboration | Slice 14 (rule 1) |
| 2026-06-05 | [AI-IDEA] Trip budget & burn-down: group sets optional budget; expenses burn it; "€140 left" chip on trip home. Pure arithmetic on existing data | schema mining | **Approved** → WAVE2_PLAN_SEED.md #7 |
| 2026-06-05 | [AI-IDEA] Settle-up nudge: day after trip end_date, one push "2 open balances — settle now". Uses end_date + trip_balances + minimal push (T10.5) | schema+funnel mining | **Approved** → WAVE2_PLAN_SEED.md #8 |
| 2026-06-05 | [AI-IDEA] QR invite: render existing invite token as QR on screen; in-person groups join by pointing a camera. join_trip unchanged | code mining | **Approved** → WAVE2_PLAN_SEED.md #6, candidate first slice |
| 2026-06-05 | Place resolution: OCR address → platform geocoder, cross-validated with EXIF GPS; introduces `places` table (keystone for TripMap/Atlas/operators/ratings) | founder + elaboration | **Approved** → W2-1 extension |
| 2026-06-05 | Silent save-place-to-contacts (permission asked only on first use) + trip-private place rating (no public UGC) — both land on the Wave-3 place detail screen | founder | Ledger → W3 (places stored from W2-1, nothing lost) |
| 2026-06-05 | Bill plausibility via route (founder): receipt's resolved place vs the group's actual GPS trail — off-route receipts get a soft "off-route" badge (possible wrong bill / joke / scam). MUST be a signal, never auto-rejection: legit false positives include online bookings, tolls, pre-trip purchases. Needs ghost-trail data | founder | Ledger → W3 (TripMap prerequisite) |
| 2026-06-05 | Dispute a split (founder): member can reject their share of an expense with a reason; payer notified; resolution = edit/remove/keep. Design weight: disputed shares need a status that the settle-up engine respects (exclude-until-resolved vs include-with-flag — decide at spec); share-invariant must hold through resolution. Trip-private, no moderation surface | founder | Ledger → W3, candidate to pull into W2 spec session as settle-family item |
| 2026-06-05 | Booking gateway vision (founder): Expedia-class lodging affiliates, flight-number resolution vs IATA/aviation APIs, trains, cruises. Revenue + enrichment play. Parked: partnership/compliance-heavy; schema hooks (plan-item kind + external_ref) ship FREE in W2 EventList so the door stays open. Evaluate seriously at W3 gate alongside operator track (same partnership muscle) | founder | Ledger → W3 gate; hooks in W2 |
| 2026-06-05 | [AI-IDEA] Spending rhythm in Tally/Wrapped: expenses now carry captured_at/lat/lng (Slice 14) distinct from created_at — Wave-3 Tally can show WHEN/WHERE money flows ("your crew peaks at dinner, Trastevere is your wallet's weakness"). Zero new collection; pure analysis of receipt metadata | schema mining (Slice 14) | Ledger → W3 planning (Tally/Wrapped scope) |
| 2026-06-05 | Internal admin / flight-control dashboard (founder): ops + support surface — health, users, trips, error rates, cost, secrets, password resets, "call-center" support tier. NOT `web/apps/operator-console` (customer-facing B2B, W3-gated). **Evaluation (build-vs-rent + security):** ~80% already exists, audited & free — Supabase dashboard does secrets (Vault), user admin, password-reset emails; provider status pages do health; env files only hold the public anon key (real secrets already in Vault, not env). **Do NOT build a homegrown secrets manager or password-setter** — highest-value attack surface; re-implements audited infra worse; needs separate admin-auth+MFA, per-action audit log, role separation, and punches through the RLS privacy promise via service-role. Phasing: (1) now→early-W3 RENT (Supabase + provider consoles); (2) cheap win = read-only internal status/dependency page (no powers); (3) W3 when support load justifies = THIN, role-separated, audit-logged support console — read-mostly, safe actions only (lookup, reset-password *email*, resend invite), secrets stay in Vault/Doppler NEVER homegrown | founder | Ledger → W3 support console (thin/audited); secrets+password UI = **rent permanently, do not build**; status page = optional early win |
| 2026-06-05 | Notifications & action funnel (founder): one subsystem to funnel any workflow's "tell the user / ask them to act" into a consistent place across channels (in-app inbox + push via existing FCM + email later), each item optionally carrying a deep-linked action. **Unifies** scattered prompts: S17 lifecycle (replaces the button wall — prompt becomes a notification w/ Accept/Object), S22 settle-nudge, S19 dispute/proposal alerts, S21 RSVP, S15 joins. **Distinct from** the Activity feed (log of what happened) — notifications are per-user, read/unread, actionable. Producers = DB triggers/RPCs + scheduled cron + (rarely) client; anti-nag centralized in per-type channel prefs. Contextual banners render from the same notification rows (one source of truth). Design memo: `docs/design/NOTIFICATIONS.md`. **Consolidates** several roadmap items into producers of one primitive. | founder | Ledger → **W3 pillar** (shares notification primitive with the admin dashboard); S17.1 lifecycle-UX built to converge toward it; S22 nudge = interim producer, absorbed later |
| 2026-06-05 | Provider throttling & quota resilience (founder, MS-Graph scar): every external call is throttle-prone + quota-bounded; silent throttle → blind wall → ticket storm. Two layers — (1) runtime handling behind the seam: respect Retry-After, backoff+jitter, transient-vs-quota-exhausted, circuit-breaker, **cache to avoid the call** (FX rates are the prime cacheable case), fail loud+safe; (2) observability: structured `provider_throttled` telemetry + persisted incident log + quota-burn vs documented ceilings → **the concrete substance of the internal dashboard** (react before users do). Standard doc: `docs/design/PROVIDER_RESILIENCE.md`. Interim (now): fail loud+safe (S20 FX already meets). Target: build WITH the abstraction layer + dashboard | founder | Ledger → W3 (with abstraction layer + dashboard); interim bar met; standard doc written |
| 2026-06-05 | Vendor-abstraction / resilience layer (founder): decouple from vendor wiring to enable swap / fallback / DR. **Architect's split (not blanket-abstract):** (a) stateful core (Supabase: PG+RLS+auth+storage+fns+realtime) is NOT cheaply swappable and shouldn't be — mitigate via a real **DR plan** (automated backups, tested restore, periodic export, self-host-PG escape path), not an abstraction; (b) swap-seams worth building where cheap + high-ROI: **email provider interface + fallback** (closes the Brevo OTP SPOF — pull FORWARD as pre-launch, it's small), **FX provider interface** (already half-done; fold into the tracked FX Edge-Function refactor), **push** (FCM behind iface for future APNs), analytics already loosely coupled; (c) cross-vendor load-balancing applies to the stateless edge only (Vercel/Edge Fns), not the DB — real-scale, not now. Keep honoring docs/architecture/DEPENDENCIES.md principle 2 (seams we own) for all NEW integrations | founder | Ledger → W3 for (a) DR plan + broad seams; **(b) Brevo email fallback pulled to pre-launch**; (c) deferred to real-scale |
| 2026-06-07 | **Postcard** (pkg `vamo_postcard`, founder-named): place→visual **backdrop** (web venue photo → static map → styled fallback) rendered behind any captured artifact — receipt / note / photo / video. The resolve-and-render logic already lives in the Capture view; this is an **extraction into a reusable package**, not a new build. Rides the already-built `places` keystone (`0011`), so the cost assumption that filed this under W3 is **stale**: the EXIF/address-derived core needs **NO device-location permission → W2-eligible** (rule 2: slice-sized, existing plumbing; rule 1: capture-time geo is irreplaceable data). The **live device-location** flavor stays W3 **TripMap**; **audio/video-pinned** captures reach W4 **TripReel**. Forward-compat note: capture tables (`trip_photos`/`trip_notes`/new `trip_videos`) currently lack lat/lng — adding `captured_lat/lng/at` at capture time is the irreplaceable-data hook (rule 1). Spec: `docs/POSTCARD_SPEC.md` | session + code/schema mining | Ledger → **founder picks wave**; W2 core eligible (places built); spec written |
