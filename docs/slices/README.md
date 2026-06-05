# Slice tracker — Wave 2 (the real stage)

Living status; specs stay sealed. Conventions: `docs/CONVENTIONS.md`.
Updated: 2026-06-05.

| Slice | Implements | Status | Notes |
|---|---|---|---|
| S15 | W2·R9 (QR invite) | ✅ done | join deep-link hardening landed separately (fix branch) |
| S16 | W2·R1 (roles), W2·R2 (push) | 🔶 code-complete | manual: hourly heartbeat schedule, device push test; assetlinks fingerprint rides with S17 |
| S17 | W2·R3 (lifecycle) | 🔶 in review (`feature/trip-lifecycle`) | 4 P1 fixes pending (syntax, guard kills member/cron transitions, settlements 0007 regression, DELETE-after-close); merge gated on cloud smoke; deemed-close cron gated on S22 push ("no notice, no deemed consent") |
| S18 | W2·R4 (TripBoard) | ⬜ | |
| S19 | W2·R5 (money governance I) | ⬜ | D1 state machine + A1 dispute window |
| S20 | W2·R6 (money governance II) | ⬜ | budget + FX constant-rate (D3/D4) |
| S21 | W2·R8 (EventList) | ⬜ | |
| S22 | W2·R7 (close report) + P1 nudge | ⬜ | + FCM UNREGISTERED pruning (S16 finding) |
| S23 | W2·R10 (AI theme resolver) | ⬜ | |
| S24 | P1 retention basics | ⬜ | |
| S25 | P1 share pages | ⬜ | domain live (vamo.world) — ungated |

In-flight fixes (merge before S17): `fix/join-deeplink-single-handler`
(reviewed, one nit: `ScaffoldMessenger.maybeOf`), `fix/web-share-and-lime-primary`.

Wave-1 slices S1–S14: shipped and verified (v0.1.0). Gate check after S22.
