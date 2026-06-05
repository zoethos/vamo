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

## Ledger

| Date | Idea | Source | Triage |
|------|------|--------|--------|
| 2026-06-05 | Receipt→stop pipeline (EXIF geo on expenses now; stops in W3; own-photo place matching W3-4) | founder + elaboration | Slice 14 (rule 1) |
| 2026-06-05 | [AI-IDEA] Trip budget & burn-down: group sets optional budget; expenses burn it; "€140 left" chip on trip home. Pure arithmetic on existing data | schema mining | **Approved** → WAVE2_PLAN_SEED.md #7 |
| 2026-06-05 | [AI-IDEA] Settle-up nudge: day after trip end_date, one push "2 open balances — settle now". Uses end_date + trip_balances + minimal push (T10.5) | schema+funnel mining | **Approved** → WAVE2_PLAN_SEED.md #8 |
| 2026-06-05 | [AI-IDEA] QR invite: render existing invite token as QR on screen; in-person groups join by pointing a camera. join_trip unchanged | code mining | **Approved** → WAVE2_PLAN_SEED.md #6, candidate first slice |
| 2026-06-05 | [AI-IDEA] Spending rhythm in Tally/Wrapped: expenses now carry captured_at/lat/lng (Slice 14) distinct from created_at — Wave-3 Tally can show WHEN/WHERE money flows ("your crew peaks at dinner, Trastevere is your wallet's weakness"). Zero new collection; pure analysis of receipt metadata | schema mining (Slice 14) | Ledger → W3 planning (Tally/Wrapped scope) |
