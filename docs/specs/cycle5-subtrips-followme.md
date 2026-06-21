# Cycle 5 — Subtrips (M) + "Follow me" (I) → competitive differentiation

_Drafted 2026-06-21. Both are Tier-2 advanced features (post-beta maturity). Each reshapes the
membership/RLS model; each gets richest once Trip Map exists._

## M — Subtrips (peer, no-admin, toggle-gated)
**Differentiation.** Groups split up constantly; today that pollutes the main plan or leaves the app.
No competitor models a parallel, collectively-owned sub-itinerary.

**The crux — two model problems, not UI:**
1. **A new peer permission scope.** The main trip is owner/co-admin (`can_edit_trip_content`). A subtrip
   has **no admin — every participant edits equally.** New tables (`subtrips`, `subtrip_members`), new
   RLS ("any member of *this* subtrip edits *its* content"), and conflict handling for concurrent peer
   edits (existing sync + last-write-wins).
2. **The money touchpoint.** A subtrip expense splits among **only the subtrip roster**, not all trip
   members. Today `equalSplit` splits across all active members and the server recomputes that —
   subtrips reopen **subset-splitting**, handled server-side the same disciplined way as S50 (recompute
   over the subtrip roster, share-sum invariant holds).

**Phases:**
- **P0** — admin **toggle** (trip setting, at creation + editable later) → when on, any member creates a
  subtrip, picks participants, adds **parallel plan items**. No admin; peers edit. **No money.**
  (See `docs/slices/M_P0_SUBTRIPS_PROMPT.md`.)
- **P1** — subtrip **rolls up to the parent timeline** + **per-subtrip expenses reconciling into the main
  split** (the subset-split work).
- **P2** — subtrip-scoped **journey replay** branch — needs Trip Map.

**Decisions:** roster mutability mid-subtrip; can a non-participant member see a subtrip exists; peer
conflict-resolution policy.

## I — "Follow me" — remote guests + safety
**Differentiation.** Family/friends who aren't traveling still want in; solo travelers want someone to
know they're okay. Emotional + retention + viral — but the highest-liability item in the roadmap.

**The crux — privacy/consent + liability, escalating by phase:**
- **Guest = a new read-only role tier** — sees the *shared story* (curated moments/timeline),
  explicitly **not** expenses/balances, and can't edit. RLS must wall off money.
- **Live location (P1)** is the privacy escalation — **per-member explicit opt-in, revocable,
  time-scoped to the trip.** Overlaps Trip Map's live path.
- **Safety (P2)** is the liability zone — keep it **soft**: "I'm safe" check-ins + inactivity nudges to
  guests. **No** emergency-response / SOS-dispatch / any guarantee. Clear disclaimers.

**Phases:**
- **P0** — add a **guest/follower** (read/follow only) via the existing invite UX; guest sees shared
  moments; no edit, no money.
- **P1** — **live journey following** (opt-in location) + guest reactions — pairs with Trip Map.
- **P2** — **soft safety**: check-in / inactivity alerts. Conservative, disclaimed, legally reviewed.

**Decisions:** exactly what a guest sees; how far into "safety" before it implies a promise (recommend:
stop at check-ins/inactivity, no SOS dispatch); guest-vs-member UI boundary.

## Sequencing
1. **M before I.** M is self-contained (group-internal, no external party, no liability); risk is
   modeling you control. I drags in external parties + privacy + liability.
2. **Trip Map is a soft prerequisite** for the richest halves (M-P2 replay branch, I-P1 live follow).
3. Natural order: **M-P0/P1 → I-P0 → (Trip Map) → M-P2 / I-P1 → I-P2 (soft safety, last & cautious).**
4. **One consolidated RLS/role pass** — owner / co-admin / member / **subtrip-peer** / **guest** — so the
   membership core isn't refactored twice.

## The one thing to flag up front
**I-P2 (safety) is the single highest-risk item in the roadmap** (duty-of-care). Ship I **without P2
first**, validate guest-following, and treat safety as a separate, **legally-reviewed** decision — not a
default phase.

## Maturity gate
Post-beta: assumes a stable core, real group usage (M), and enough trust/scale to justify the privacy
surface (I).
