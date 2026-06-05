# Trip closure — deemed acceptance

Source: `docs/design/MONEY_GOVERNANCE.md` D2 (amended 2026-06-05) ·
rationale `docs/design/CLOSURE_PATTERNS.md` · implements in S17.

The one-sentence contract: **closing a trip stops new spending after a
14-day silence-is-consent window; financial finality arrives later, per
member, at their own settlement confirm — and dissent is always loud.**

## Lifecycle state machine

```mermaid
stateDiagram-v2
    [*] --> active

    active --> cancelled : cancel_trip\n(owner only, before start_date)
    active --> closing : request_trip_close (owner)\nOR all members completed_at

    state closing {
        [*] --> window_open
        window_open --> window_open : member accepts (explicit)\nmember objects (reason)
        note right of window_open
            14-day window from close_requested_at
            day 7 — single reminder (close_warned_at)
            silence = deemed acceptance
        end note
    }

    closing --> closed : all active members\naccepted explicitly (early close)
    closing --> closed : window expired\nAND no open objection (deemed)
    closing --> closed : owner force-close\n(open objection RECORDED in report)
    closing --> unresolved : 6 months after close_requested_at\nAND objection still open (auto, warn at month 5)

    closed --> [*]
    unresolved --> [*]
    cancelled --> [*]
```

## What each state permits

| | new expenses / captures / plan edits | settlements | disputes (share rejection) |
|---|---|---|---|
| `active` | ✅ | ✅ | ✅ |
| `closing` | ✅ (trip is still live) | ✅ | ✅ |
| `closed` | ❌ (RLS-blocked) | ✅ **stays open** | ✅ until own settle-confirm (A1) |
| `unresolved` | ❌ | ✅ | ✅ until own settle-confirm |
| `cancelled` | ❌ | ❌ | — |

Construction analogy (see CLOSURE_PATTERNS P4): `closed` = practical
completion ("no new work"), the post-close settling period = defects
liability period, per-member settlement confirm = final certificate.

## The dance, end to end

```mermaid
sequenceDiagram
    autonumber
    actor O as Owner
    actor M1 as Member (engaged)
    actor M2 as Member (ghost)
    participant T as Trip (DB + RLS)
    participant J as trip-lifecycle-jobs (daily cron, CRON_SECRET)
    participant P as send-push

    O->>T: request_trip_close()
    T->>T: lifecycle = closing, close_requested_at = now()
    T->>P: notify all active members
    P-->>M1: "Trip closing — review. Auto-closes in 14 days."
    P-->>M2: (same — ignored)

    M1->>T: accept_trip_close()  — explicit
    Note over M2: silence

    J->>T: day 7 — close_warned_at IS NULL?
    T->>P: single reminder (anti-nag: once, ever)
    P-->>M2: "7 days left to review the close."

    alt M2 stays silent
        J->>T: day 14 — window expired, no open objection
        T->>T: lifecycle = closed (M2 deemed accepted)
        T->>P: closed — report lists M1 explicit / M2 deemed
    else M2 objects with reason
        M2->>T: object_to_trip_close(reason)
        Note over T: trip held in closing — objection visible to all
        alt resolved / withdrawn
            M2->>T: withdraw objection → deemed/explicit path resumes
        else owner breaks the deadlock
            O->>T: force_close_trip()
            T->>T: lifecycle = closed (objection FLAGGED in report)
        else nobody moves
            J->>T: month 5 — warn (objected trips only)
            J->>T: month 6 — lifecycle = unresolved, notify, badge in Expenses "Earlier"
        end
    end

    Note over T: AFTER closed/unresolved — settling still open:
    M1->>T: confirm own settlement → M1's dispute window closes (A1)
    M2->>T: dispute allowed until M2's own settle-confirm
```

## Invariants (review checklist)

1. **Silence never blocks; only a reasoned objection does.** No path waits
   indefinitely on a non-responder.
2. **Deemed ≠ hidden.** Close report always distinguishes explicit accept /
   deemed accept / objected-then-forced. Never merged.
3. **`settlements` writable in `closing`/`closed`/`unresolved`** — blocked
   only in `cancelled`. (The banner says "settling still open"; RLS must
   agree.)
4. **One reminder, ever** (`close_warned_at`). Daily cron must be idempotent
   — re-running a day never re-sends.
5. **`unresolved` is reachable ONLY via an open objection.** A trip with all
   silence closes clean at day 14.
6. **Force-close never erases the objection** — it travels into the report
   (squeeze-out with appraisal rights).
7. Lifecycle transitions happen **only via RPCs** (`request_trip_close`,
   `accept_trip_close`, `object_to_trip_close`, `force_close_trip`,
   `cancel_trip`, deemed-close job) — never direct column updates by members.
8. Cron job authenticates with `x-cron-secret` (never the bare heartbeat
   pattern) and records `record_job_heartbeat` per run.

## rls_smoke cases (state-based, per the "no error ≠ it worked" rule)

- Member INSERT/UPDATE/**DELETE** expense on closed trip → **blocked**
  (DELETE matters: `FOR ALL` policies apply USING to deletes — found in
  S17 review)
- Member settlement write (own, as participant) on closed trip → **ALLOWED**
- Member writes a settlement **between two other members** → **blocked**
  (0007 participant-scoping regression lock)
- Any write on cancelled trip → **blocked** (incl. settlements)
- Deemed close: window expired + silent member → lifecycle = `closed`
- Open objection at window expiry → lifecycle stays `closing`
- All members mark complete → lifecycle auto-enters `closing`
- Member early-accept completes → `closed` (member-driven transition must
  pass the lifecycle guard — S17 review finding)
- Co-admin cannot cancel/close/force (owner-only transitions)

## Sequencing constraint (S17 review P2)

**No notice, no deemed consent**: the day-14 deemed close must not run in
production before lifecycle push notifications exist (S22). Until then,
either the cron schedule stays off or S22's notify path ships first.
