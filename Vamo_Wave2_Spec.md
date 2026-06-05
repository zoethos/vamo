# Vamo — Wave 2 Spec ("open daily": plan, agree, go)

Status: DRAFT for founder approval · 2026-06-05
Inputs: `docs/WAVE2_PLAN_SEED.md` (sealed with this spec), `docs/design/MONEY_GOVERNANCE.md` (decided constitution), `docs/DESIGN_BRIEF.md`, Wave-1 spec conventions. Already shipped in-wave: identity pass, OCR scan-to-fill + places, Expenses overview.

---

## 1. Problem statement

Wave 1 made Vamo useful at two moments: when money is spent and when it's settled. Between and before those moments the app has no reason to be opened — and episodic usage is the #1 risk in the financial model (dormancy/churn assumptions dominate every scenario). Groups currently plan trips in WhatsApp threads where costs, consent, and itineraries evaporate; Vamo captures none of that intent and earns no pre-trip or daily engagement.

## 2. Goals

1. **Stretch the engagement window**: users open Vamo before the trip (planning/proposals) and daily during it (events/board) — measured, not hoped.
2. **Make group money governable**: proposals, consent, budget, and FX policy per the money-governance constitution — deterministic math, human judgment.
3. **Give trips an honest lifecycle**: member-complete → close-with-acceptance → reconciliation report; no zombie trips.
4. **Raise the viral coefficient's cheapest lever**: QR invite for in-person groups.
5. **Finish the growth seed**: AI theme resolver (global cache) and view-before-install share pages.

## 3. Non-goals (Wave 3+ or never-this-wave)

- **TripMap / ghost-trail / any live location** — Wave 3's moat, untouched here.
- **Tally charts/Wrapped** — the Expenses overview period strip is the only stats surface this wave.
- **Place ratings, save-to-contacts, off-route plausibility** — need the Wave-3 place screen.
- **Booking/affiliate integrations, flight resolution** — schema hooks only (`kind`, `external_ref`); partnerships are a gate conversation.
- **Translations** — i18n rules apply to all new screens; shipping translated strings stays out.
- **Dark mode, OCR cloud fallback, public anything** — out.

## 4. User stories (by persona, priority order)

**Organizer (owner)**
- As an organizer, I want to propose planned costs (hotel, ferry) before the trip so the group agrees before money is spent.
- As an organizer, I want to set a budget (informational or formal) so spending has a shared reference.
- As an organizer, I want to add expected currencies at fixed market rates so conversions are predictable and argument-proof.
- As an organizer, I want to promote a co-admin so planning doesn't bottleneck on me.
- As an organizer, I want to cancel a trip before it starts if consensus fails, or close it after, knowing everyone must accept the close.

**Member**
- As a member, I want to accept or reject my share of any cost with a reason, without blocking anyone, so disagreement is recorded like an adult.
- As a member, I want to mark my own journey complete even if others continue, so my trail ends when I do.
- As a member, I want to see exactly what I'm walking into at close: one report with totals, disputes, drift.
- As a member standing next to my friends, I want them to join by scanning a QR so nobody types links.

**Trip crew (collective)**
- As a crew, we want a shared board of itinerary items and events with RSVP so the plan lives where the money lives.
- As a crew, we want every trip's share card themed to our destination automatically.

**Edge personas**
- As a leaver with open disputes, I want a clear warning that leaving freezes my responses.
- As an invitee without the app, I want the invite link to show me the trip before any store visit (share pages).

## 5. Requirements

### P0 — the wave is these
| # | Requirement | Acceptance criteria (summary) |
|---|---|---|
| R1 | **Roles**: owner / co-admin / member (enum extension + grants UI + RLS) | co-admin can edit plan/proposals/budget/FX; member cannot; rls_smoke cases |
| R2 | **Push plumbing finished** (T10.5 completion) | close/cancel/nudge notifications deliverable on Android |
| R3 | **Trip lifecycle**: member `completed_at`; close = all-active-accept or owner force; cancel pre-start; read-only after close (RLS); 6-month auto-`unresolved` (warn at 5) | write-after-close blocked in rls_smoke; cancel notifies; unresolved badge in Expenses "Earlier" |
| R4 | **TripBoard plan items**: CRUD, `kind` (lodging/flight/train/activity/other), `external_ref`, shared lists | items sync offline-first like expenses; i18n + signals wired |
| R5 | **Money governance I**: expense `status` (proposed/committed/cancelled), share `response` (pending/accepted/rejected+reason); settle counts committed only; **hard display rule** (disputed ≠ silent) | state machine per memo incl. R1-netting dispute window; share invariant tests; balances show "disputed by X" |
| R6 | **Money governance II**: budget (informational/formal + typed over-commit), FX constant-rate table (market-captured, refresh-forward-only, no manual rates) | proposals flag over-budget; refreshed rate affects new expenses only (test) |
| R7 | **Close report**: committed totals, consent ledger (pending/rejected + reasons), cancelled proposals, FX drift vs daily, unresolved marker | generated at close + regenerated on later dispute until member-settle-confirm |
| R8 | **EventList**: events with date/place, RSVP per member; Activity feed shows them | RSVP states sync; event fits plan-item schema (`kind: activity` specialization) |
| R9 | **QR invite**: token as QR + scanner entry on join screen; `member_invited {channel}` | scan→join round-trip works phone-to-phone |
| R10 | **AI theme resolver** per `docs/AI_THEMING_SPEC.md` | cache hit serves without LLM; validation gates enforced; fallback intact |

### P1 — in-wave if the wave runs clean
- Settle-up nudge on close (needs R2+R3) — anti-nag rule from seed.
- Retention basics: offload media / leave-&-purge (with R5 warning) / owner delete-for-everyone.
- Web share-pages (`web/apps/share-pages`) — **externally gated on domain purchase**.
- Secondary-currency visibility line in Expenses period strip.

### P2 — architectural insurance only
- Proposal attachments (quotes/screenshots) — plan items get `attachment_path` column now, no UI.
- Event reminders; recurring events.
- Co-admin audit trail (who changed what) — `updated_by` columns now, no surface.

## 6. Success metrics (the Wave-2 → Wave-3 gate reads these)

**Leading (2–4 weeks after testers):**
- Pre-trip engagement: ≥50% of trips with ≥2 members get ≥1 proposal response before start_date.
- During-trip DAU: ≥40% of active-trip members open daily (target; 25% = concern).
- QR share of joins: any nonzero validates the lever; >30% = double down.
- Theme cache hit rate climbing weekly (resolver economics proof).

**Lagging (gate inputs):**
- Day-after-close retention: member opens app within 7 days of trip close ≥35%.
- Second-trip creation rate within 30 days ≥20%.
- Disputes: ≥90% of rejected shares carry a reason (mechanism used as designed, not rage-tapped).

## 7. Open questions

- **(founder, non-blocking)** Domain: `vamo.world` purchase — gates share-pages and privacy URL only.
- **(engineering, blocking R3)** Scheduled jobs: pg_cron availability on current Supabase plan vs. scheduled Edge Function — pick during S16.
- **(design, non-blocking)** Close report rendering: in-app screen first; PDF export later?
- **(founder, during S19)** Proposal commit rights: co-admin always, or owner-only when over formal budget?

## 8. Slices (build order; each demo-able; estimates in dev-days)

| Slice | Scope | Est | Depends |
|---|---|---|---|
| S15 | QR invite (R9) | 0.5 | — |
| S16 | Push finish + roles + scheduled-job decision (R1, R2) | 1.5 | — |
| S17 | Trip lifecycle + RLS + smoke cases (R3) | 2 | S16 |
| S18 | TripBoard plan items + lists (R4) | 2 | — |
| S19 | Money governance I — states/responses/display rule (R5) | 2.5 | S18 |
| S20 | Money governance II — budget + FX table (R6) | 1.5 | S19 |
| S21 | EventList + RSVP + Activity enrichment (R8) | 1.5 | S18 |
| S22 | Close report + settle nudge (R7, P1-nudge) | 1.5 | S17, S20 |
| S23 | AI theme resolver (R10) | 2 | — |
| S24 | Retention basics (P1) | 1 | S17 |
| S25 | Share pages (P1, domain-gated) | 2.5 | domain |
| — | **Total ≈ 18.5 dev-days** (+ deps-KGP chore 0.5 anytime) | | |

Gate check after S22: leading metrics readable → go/kill on Wave 3 prep.

## 9. Timeline considerations

No hard external deadlines. Internal sequencing: **Play internal build should ship after S15–S17** (testers get lifecycle-sane trips + QR; money governance arrives as an update they witness — good beta theater). The deps-KGP chore rides before the store build. Share-pages float to whenever the domain exists.

---
*Seal: with this spec approved, `WAVE2_PLAN_SEED.md` is closed to additions; new ideas → `docs/AI_IDEATION_GOVERNANCE.md` ledger → Wave-3 planning.*
