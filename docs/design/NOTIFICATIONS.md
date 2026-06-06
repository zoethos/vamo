# Notifications & action funnel — evaluation

Status: **adopted as the Wave-3 destination** (founder review 2026-06-05) ·
not yet scheduled. Trigger: S17 lifecycle controls felt like they "should be a
notification, not a button wall." That generalizes.

## Binding boundaries (founder review — these are guardrails, not nice-to-haves)

1. **Notifications support the workflow; they do NOT replace in-app workflow
   UI.** Per Android/Apple HIG, notifications are timely, relevant,
   user-controlled, actionable — but never the *primary* control surface. The
   trip screen still owns the workflow; notifications point to it.
2. **Not a dumping ground.** Only items needing **awareness or action** become
   notifications. Routine events stay in the Activity log, not the inbox.
3. **Push sensitivity.** Disputes, objections, and money prompts must NOT leak
   sensitive detail to lock screens — generic titles, detail behind unlock
   (Android notification visibility / iOS equivalent).
4. **Ops/admin alerts stay separate** from user notifications even though they
   share a conceptual shape (different security surface; ties to the dashboard).
5. **Personal, sparse, actionable, permissioned, separate from Activity.**

Sources: Android notifications UX
(developer.android.google.cn/design/ui/mobile/guides/home-screen/notifications),
Android notification channels
(developer.android.com/develop/ui/compose/notifications/channels), Apple
managing notifications
(developer.apple.com/design/human-interface-guidelines/managing-notifications).

## The idea

One subsystem that funnels **anything any workflow needs to tell a user — or
ask them to do** — into a single, consistent place, deliverable across channels
(in-app inbox, push, later email). Each item optionally carries an **action**
that routes straight into the relevant flow.

## What it unifies (today these are scattered / ad-hoc)

- **Lifecycle prompts** (S17): "trip closing — accept/object", "all members
  done?" → today a button wall on the trip screen.
- **Settle-up nudge** (S22 seed): "2 open balances — settle now."
- **Close-window reminders** (S17 day-7, month-5): scheduled, currently DB-only.
- **Proposal / dispute events** (S19): "Marco disputed his share", "new cost
  proposed — respond."
- **RSVP requests** (S21): "you're invited to an event."
- **Invites / joins** (S15): "Anna joined your trip."
- **(Admin side)** throttle/quota + dependency alerts (PROVIDER_RESILIENCE
  layer 2) — same primitive, different audience; keep a separate ops channel.

Instead of each slice bolting its own banner onto a screen, they all **produce
notifications**; the notification subsystem handles surfacing + delivery.

## Crucial distinction: Notifications ≠ Activity feed

We already have an **Activity** tab (chronological log of what *happened* across
my trips — expense added, member joined). Don't conflate:

| | Activity feed | Notifications |
|---|---|---|
| Nature | passive **log** of events | **per-user**, "for you / new / act" |
| State | none (just history) | **read/unread**, optionally **actioned** |
| Action | none | may carry an action (Accept, RSVP, Settle) |
| Scope | trip events, everyone sees same | personal — your prompts, your unread |

A notification may *reference* an activity, but it adds the personal +
actionable + unread layer. They coexist.

## Proposed shape

**Data model** — `notifications` (per-user rows):
`id, user_id, type, trip_id?, title, body, action_kind?, action_payload(jsonb),
read_at, created_at, expires_at?`. RLS: own-rows only (the definer-reader rule
applies). `type` is an enum that grows per producer (close_requested,
close_window_reminder, settle_nudge, share_disputed, event_invited, …).

**Producers** (where notifications are born):
- **DB triggers / RPCs** — e.g. `request_trip_close` inserts a
  `close_requested` notification for each active member (service-role writer,
  same GUC pattern). Disputes, proposals, joins similarly.
- **Scheduled jobs** — the lifecycle cron (day-7, settle nudge) inserts
  notifications instead of (or alongside) raw pushes.
- **Client** — rarely; mostly server-authoritative so it's consistent
  across devices.

**Channels (the funnel)** — one notification, multiple deliveries:
- **In-app inbox** (always) — a bell/inbox with unread badge.
- **Push** (opt-in) — reuse the existing FCM plumbing (S16 `send-push`); a
  notification flagged push-worthy fans out to the user's devices.
- **Email** (later) — Brevo, for high-value/away-from-app.
Per-user preferences decide which types go to which channel (anti-nag lives
here, centrally — not re-implemented per workflow).

**Actionability** — `action_kind` + payload → tapping deep-links into the flow
(accept close, open RSVP, settle up). This is the **elegant replacement for the
S17 button wall**: the lifecycle prompt becomes a notification item with
Accept/Object actions, surfaced contextually.

**Surfacing** — two views of the same data:
- The **inbox** (list of all notifications, read/unread).
- **Contextual banners** on relevant screens **rendered from the same
  notification rows** — so the "trip closing" banner *is* the notification,
  shown in context. One source of truth, no duplicate logic.

## What this consolidates on the roadmap

Adopting this reframes several planned items as **producers/consumers** of one
subsystem rather than separate features:
- S22 settle-nudge → a notification type + the push channel.
- S17 lifecycle reminders → notification types.
- S21 RSVP request, S19 dispute/proposal alerts → notification types.
- The S16 push plumbing → the push *channel* of this subsystem.

That's a planning win: build the primitive once, every workflow plugs in.

## Sequencing — recommendation

This is a **subsystem**, not a slice — likely a **Wave-3 pillar** (alongside
the dashboard, which shares the notification primitive on the ops side). Do
**not** build it now mid-internal-build.

For the **immediate S17 problem**, do the small **S17.1 lifecycle-UX** fix
(phase-aware gating + quiet overflow + contextual banner) — but design it to
**converge**: the contextual banner is the first thing that later reads from
notification data. No throwaway work.

Interim producers (S22 settle nudge) can ship as targeted features now and be
**absorbed** into the subsystem when it lands — as long as we keep their copy
+ routing in catalogued, reusable form (not bespoke one-offs).

## Open questions (founder)

1. **Inbox placement** — a dedicated bell/inbox in the nav, or fold into the
   Activity tab as an "actionable" filter? (Lean: distinct bell; Activity stays
   a log.)
2. **Push default** — opt-in per type, or sensible defaults with per-type
   mute? (Lean: defaults + mute; anti-nag centralized.)
3. **Wave-3 pillar vs pull-earlier** — is this important enough to slot a
   foundational slice before Wave 3 (so S21/S22 produce into it from day one),
   or build those as interim features and consolidate later?
4. **Ops notifications** (throttle/dependency alerts) — same table with an
   `audience` flag, or a separate internal channel? (Lean: separate — different
   security surface, ties to the admin dashboard.)
