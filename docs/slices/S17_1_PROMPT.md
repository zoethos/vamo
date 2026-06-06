# S17.1 — Lifecycle UX fix (phase-aware + quiet) · blocks internal build

**Branch:** `fix/lifecycle-ux` · **Est:** ~0.5 dev-day · **Depends:** S17 merged
**Why:** on a pre-start trip the banner shows "I'm done" + "Request close"
(both semantically wrong before a trip starts) plus a 3-button wall that's too
loud. Two problems: **phase-wrong triggers** + **visual noise**.
**Scope:** UI only — no schema, no RPC change. (The RPCs are fine; this is
gating + placement.) Converges toward `docs/design/NOTIFICATIONS.md` (W3) but
builds none of it now.

## Boundary (founder, from NOTIFICATIONS review)
Notifications support workflow, don't replace it. This slice keeps lifecycle
control **in the trip UI**, just phase-correct and quiet. The only prominent
surface is the `closing` banner (genuinely time-sensitive).

## 1. Phase-aware gating (the bug)

Define trip phase from `lifecycle` + `start_date`:
- **pre-start** = `lifecycle=active` AND `start_date` is set AND in the future
- **ongoing** = `lifecycle=active` AND (`start_date` null OR ≤ today)
  (undated trips treated as ongoing — decidable rule; refine later if needed)
- **closing / closed / cancelled** = by lifecycle

Controls per phase:

| Phase | Owner | Member |
|---|---|---|
| pre-start | **Cancel trip** (only) | — |
| ongoing | **Request close**; **I'm done** | **I'm done** |
| closing | banner: Accept / Object (+ owner force if objection) | banner: Accept / Object |
| closed/cancelled | read-only banner | read-only banner |

Key fixes vs current: **"I'm done" and "Request close" never show pre-start**;
**Cancel never shows once ongoing** (it's pre-start-only anyway — the RPC
enforces, the UI must match).

## 2. Quiet placement (the noise)

- **Remove the active-state button wall** from `TripLifecycleBanner`.
- Owner lifecycle actions (Cancel pre-start / Request close ongoing) move into
  the trip app-bar **overflow (⋯) menu** — present, not shouting.
- **"I'm done"** (member action, ongoing only) is a single quiet entry — in the
  same overflow menu, or one understated row at the bottom of the trip — not a
  prominent button. (Pick whichever reads cleaner; overflow is fine.)
- **`closing` banner stays prominent** exactly as it is — it's the one
  time-sensitive state that warrants a contextual banner. Don't touch it beyond
  what's needed.
- closed/cancelled read-only banner unchanged.

## 3. Tests (negative-assertion, per CONTRIBUTING)

Widget tests on the trip screen / banner:
- **pre-start trip:** "I'm done" **absent**, "Request close" **absent**;
  overflow contains **Cancel** only.
- **ongoing trip:** overflow contains "Request close" (owner) + "I'm done";
  **Cancel absent**.
- **member (non-owner) ongoing:** "I'm done" present; no owner close/cancel.
- **closing:** banner + Accept/Object present (regression guard — unchanged).
- No active-state button wall rendered (assert the old buttons are gone).

`melos run ci` green. No smoke change (no DB delta).

## 4. RUN.md — note the phase-aware lifecycle controls + overflow placement.

## 5. Reviewer checklist
- [ ] Pre-start shows neither "I'm done" nor "Request close" (phase bug fixed)
- [ ] Cancel shown only pre-start; close/done only ongoing
- [ ] Active-state button wall gone; owner actions in overflow; "I'm done" quiet
- [ ] `closing` banner untouched (still prominent, Accept/Object)
- [ ] Negative-assertion widget tests cover each phase
- [ ] No schema/RPC change; ARB strings for any new/moved labels
