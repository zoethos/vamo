# Slice tracker — Wave 2 (the real stage)

Living status; specs stay sealed. Conventions: `docs/CONVENTIONS.md`.
Updated: 2026-06-05.

| Slice | Implements | Status | Notes |
|---|---|---|---|
| S15 | W2·R9 (QR invite) | ✅ done | join deep-link hardening landed separately (fix branch) |
| S16 | W2·R1 (roles), W2·R2 (push) | 🔶 code-complete | manual left: hourly heartbeat schedule (dashboard), device push test after phone rebuild |
| S17 | W2·R3 (lifecycle) | ✅ merged | review P1s fixed; smoke 34/34 on cloud; `trip-lifecycle-jobs` deployed with CRON_SECRET but **unscheduled** — activates with S22 push ("no notice, no deemed consent") |
| S18 | W2·R4 (TripBoard) | ✅ merged | smoke green incl. closed-trip + ex-member plan cases; schema S21-ready (events = kind:activity) |
| S19 | W2·R5 (money governance I) | ✅ merged | smoke 51/51; forged-dispute guard (0018) + realtime parent-touch; 2 invariants verified |
| S19.1 | W2·R5 finish | ✅ merged | propose UI + governance ARB; 5 second-review fixes in; CI 189 tests; **internal-build gate cleared** |
| — | **Wave 2 internal build (S15–S19)** | 🔶 cutting | go/no-go in `docs/SHIP_INTERNAL.md`; S16 manual tail + assetlinks fingerprint, then Play internal track |
| S20 | W2·R6 (money governance II) | 🔶 approved, pre-push | budget + FX table; D4 satisfied; fixed spend-leak (definer aggregate). Then db push + cloud smoke (needs exchangerate key in vault) → merge. Follow-ups: expense conversion→constant table (D4 OCR clause); FX fetch→Edge Function |
| S21 | W2·R8 (EventList) | ⬜ | |
| S22 | W2·R7 (close report) + P1 nudge | ⬜ | + FCM UNREGISTERED pruning (S16 finding) |
| S23 | W2·R10 (AI theme resolver) | ⬜ | |
| S24 | P1 retention basics | ⬜ | |
| S25 | P1 share pages | ⬜ | domain live (vamo.world) — ungated |

In-flight fixes (merge before S17): `fix/join-deeplink-single-handler`
(reviewed, one nit: `ScaffoldMessenger.maybeOf`), `fix/web-share-and-lime-primary`.

Wave-1 slices S1–S14: shipped and verified (v0.1.0). Gate check after S22.
