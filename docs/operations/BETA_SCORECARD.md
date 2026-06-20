# Closed Beta Scorecard

Status: operating rubric · 2026-06-20.

Use this after the launch gates in `LAUNCH_GATES.md` are green and testers are
using the Firebase/Play testing build. The goal is to decide whether Vamo is
ready to widen, needs a focused fix pass, or should cut/rethink a weak loop.

Primary sources:

- PostHog EU for product telemetry.
- Firebase Crashlytics for crashes.
- Supabase provider telemetry for throttling, storage, email, and lifecycle jobs.

No gate metric should include PII, raw note text, full exception text, or money
amounts beyond already-sanitized event categories.

## Cohort And Window

- Cohort: the first closed-beta testers.
- Window: the first 14 days of real use.
- Outcome per dimension: `graduate`, `fix-first`, or `cut/rethink`.

The bars below are calibration points. At this tester volume, funnel shape and
qualitative friction matter more than exact percentages.

## Scorecard

| # | Dimension | Question | Primary signal | Candidate bar |
|---|---|---|---|---|
| 1 | Activation | Do users reach first value? | `trip_created` -> `expense_added` -> balance viewed | 60% add at least one expense; 40% reach balance view |
| 2 | Money loop | Does split/settle complete? | expense committed -> share response -> settlement | majority of multi-member trips reach at least one settlement action |
| 3 | Multiplayer | Does the group loop happen? | invite sent -> joined -> second member acts | at least one real two-person trip with both sides acting |
| 4 | Planning | Do Visit/Transfer items get used? | `plan_item_created` / updated / RSVP | testers add real itinerary items, not only dummy data |
| 5 | Closure | Do trips stop lingering? | close request / soft-close / reopen / settle events | no unexplained stuck `closing` or `soft_closed` trips |
| 6 | Growth | Do invite links spread? | `member_invited`, `invite_accepted`, web share page events | measurable invite-to-join path from link/QR/contact |
| 7 | Retention | Do testers return? | D1/D3/D7 return sessions | any meaningful D3 return; inspect by trip status |
| 8 | Quality And Trust | Is it stable and believable? | `action_failed`, Crashlytics, provider errors, tester feedback | low catalogued-error rate; no money-correctness complaints |

## Trust Veto

Money correctness, privacy leakage, broken media rehydration, or login/email
outage overrides all other good news. Treat those as `fix-first` even if the
usage funnels look promising.

## Instrumentation Audit

Before judging the scorecard, confirm these events actually land:

- Activation: `trip_created`, `expense_added`, balance/rollup view signal.
- Money: `share_response`, `settle_marked`, `settle_confirmed`.
- Multiplayer: `member_invited {channel}`, `invite_accepted {channel}`.
- Planning: `plan_item_created`, `plan_item_updated`, `event_rsvp`.
- Growth: `share_page_viewed {channel,status}`,
  `share_open_app_tapped {channel}`.
- Quality: `action_failed` with sanitized code and no raw exception details.
- Crash telemetry: tester build crashes appear in Firebase Crashlytics.

If a funnel is not instrumented, add the event before using that funnel as a
product decision gate.
