# Wave-2 → Wave-3 gate (the tester scorecard)

Status: rubric · 2026-06-07 · **C-prep artifact** (Phase C). The *decision* needs
Phase-B tester data (internal build live); this defines **what we'll measure and
how we'll decide** so the call is fast and pre-agreed once data flows.
Reads: **PostHog EU** (project 193638) + provider telemetry (`provider_throttled`,
`provider_usage_events`). No PII in any gate metric.

## How the gate works
- **Cohort:** the internal-build testers (Phase B). **Window:** first ~2 weeks of
  real use (and the Play closed-test minimum — ≥12 testers / 14 days — doubles as
  the gate cohort).
- **Outcome per dimension:** **Graduate** (good enough → build on it in W3) /
  **Fix-first** (promising but a blocker must be fixed before W3) / **Cut**
  (not working → stop investing, rethink).
- Thresholds below are **starting calibration points**, not gospel — set the real
  baseline from the first few days, then judge against it. The *shape* of the
  funnel matters more than absolute numbers at this volume.

## The scorecard

| # | Dimension | Question | Primary signal (PostHog) | Candidate bar (calibrate) |
|---|---|---|---|---|
| 1 | **Activation** | Do new users reach first value? | create_trip → add first expense → see balance, per new user | ≥60% of new testers add ≥1 expense; ≥40% reach a balance |
| 2 | **Core money loop** | Does the split/settle loop complete? | expense committed → share responded → settlement confirmed | a majority of trips with >1 member reach ≥1 settlement |
| 3 | **Multiplayer** | Does the *group* part actually happen? | invite sent → joined → 2nd member acts (expense/RSVP/settle) | ≥1 real 2-person trip with both sides acting; invite→join rate |
| 4 | **Closure dance** | Does the zombie-trip cure work? (R3) | request_close → accept/object/deemed → settle | trips reach a terminal state; few stuck in `closing`/`unresolved` |
| 5 | **Growth engine** | Do shares/invites spread? | `member_invited` by channel; `invite_accepted`; share-page views→installs | invite_accepted/invite_sent ratio; any contact/share-driven joins |
| 6 | **Retention** | Do they come back? | return sessions D1/D3/D7 per tester | any meaningful D3 return (baseline-set; retention is S24's target) |
| 7 | **Quality/trust** | Is it stable + trustworthy? | `action_failed` rate; crash-free sessions; provider throttle rate | low catalogued-error rate; no money-correctness complaints |
| 8 | **Friction (§8b)** | Where do they stall/rage? | the §8b friction signals + drop-off points in each funnel | no single step bleeding the majority of users |

## Decision rules
- **Graduate** a dimension if it clears its bar **and** qualitative tester
  feedback isn't screaming about it.
- **Fix-first** if the data shows a specific, fixable blocker (e.g. activation
  dies at one step) — fix before W3 investment in that area.
- **Cut / rethink** if a *core* dimension (1, 2, 4, 7) fundamentally underperforms
  — that's a product-thesis signal, not a polish item.
- **Trust is a veto:** any money-correctness or privacy failure (dimension 7) is
  an automatic Fix-first regardless of the other numbers — it's the whole product.

## C-prep — instrumentation audit (do NOW, before testers)
The gate is only as good as the events it reads. Before Phase B, **verify each
funnel actually fires into PostHog**:
- [ ] Activation: `trip_created`, `expense_added`, `trip_rollup_opened` events present + landing in PostHog EU.
- [ ] Money loop: `share_response` + `settle_marked`/`settle_confirmed` events fire.
- [ ] Multiplayer: `member_invited {channel}`, `invite_accepted {channel}`, join events.
- [ ] Closure: lifecycle transition events (request/accept/object/deemed) — note S22 adds nudge events.
- [ ] Growth: S25 web `share_page_viewed {channel,status}` + `share_open_app_tapped {channel}`; install attribution where possible.
- [ ] Quality: `action_failed` catalogued events; crash reporting wired.
- [ ] No PII / amounts in any of the above (privacy invariant).
- [ ] Dogfood pass (you + zoethos) confirms the events show up in PostHog as expected.

If any funnel isn't instrumented, **add it before testers arrive** — you can't
gate on data you didn't capture.

Static audit note (2026-06-07): mobile app events are catalogued in
`VamoEvent`; `/j/<token>` web share pages now emit explicit, privacy-safe
PostHog events when `NEXT_PUBLIC_POSTHOG_API_KEY` is set. Live PostHog
verification still needs a dogfood pass in the project UI.

## Notes
- Several events arrive with their slices (S22 closure nudges, S25 share-page
  views, S26 contact channel) — the audit above is also a checklist that those
  landed.
- This rubric is the **Phase C** half of `docs/ROADMAP_PHASES.md` (if created);
  the *decision* is run once Phase B onboards the cohort.
