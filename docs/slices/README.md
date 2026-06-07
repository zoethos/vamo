# Slice tracker — Wave 2 (the real stage)

Living status; specs stay sealed. Conventions: `docs/CONVENTIONS.md`.
Updated: 2026-06-07.

## Recommended sequencing (founder-approved)

1. **Fix main CI golden + merge #21** — do not start new slices on red main.
2. **S25** share pages (web-only, growth, ungated) — prompt tightened 2026-06-07.
3. **S23** AI theme (after S25; reads `trips.theme` via preview RPC).
4. **S22** close report — PR open; **held** until device + cron dry-run pass.

| Slice | Implements | Status | Notes |
|---|---|---|---|
| S15 | W2·R9 (QR invite) | ✅ done | join deep-link hardening landed separately (fix branch) |
| S16 | W2·R1 (roles), W2·R2 (push) | ✅ done | heartbeat cron firing; device push verified on S25 (lands + routes to /trips). send-push fixed (djwt→jose, npm: imports) + key rotated. Follow-up: FCM UNREGISTERED pruning (S22) |
| S17 | W2·R3 (lifecycle) | ✅ merged | review P1s fixed; smoke 34/34 on cloud; `trip-lifecycle-jobs` deployed with CRON_SECRET but **unscheduled** — activates with S22 push ("no notice, no deemed consent") |
| S18 | W2·R4 (TripBoard) | ✅ merged | smoke green incl. closed-trip + ex-member plan cases; schema S21-ready (events = kind:activity) |
| S19 | W2·R5 (money governance I) | ✅ merged | smoke 51/51; forged-dispute guard (0018) + realtime parent-touch; 2 invariants verified |
| S19.1 | W2·R5 finish | ✅ merged | propose UI + governance ARB; 5 second-review fixes in; CI 189 tests |
| S20 | W2·R6 (money governance II) | ✅ merged | budget + FX constant-rate; smoke 62/62; FX endpoint `/live` (0020) + service-writer smoke (0021); provider-resilience standard. Follow-ups: expense conversion→constant table (D4 OCR clause); FX fetch→Edge Function + throttle handling |
| S17.1 | lifecycle UX fix | ✅ merged (`5fb7721`) | phase-aware gating + quiet overflow; closing banner kept; P1 UTC fix; request-close confirm dialog; tooltip→ARB. CI 121 tests |
| S21 | W2·R8 (EventList) | 📋 prompt ready (`S21_PROMPT.md`) | events = plan items kind:activity (S18 reuse) + RSVP own-row |
| — | **Wave 2 internal build (S15–S20)** | 🔶 in progress | S16 verified; **release-signed `.aab` built** (upload key CN=Tiziano Rocca/Vamo, R8 proguard fix for ML Kit Latin-only). Next: Play internal upload → app-signing-key SHA-256 → assetlinks → testers (`SHIP_INTERNAL.md` 5–8) |
| — | **Notifications subsystem** | 🔭 W3 pillar (`design/NOTIFICATIONS.md`) | adopted as destination; lifecycle/nudge/RSVP/dispute become producers; ops alerts separate |
| S22 | W2·R7 (close report) + P1 nudge | 🔶 PR #20 | device + cron gate before merge; cron unscheduled |
| S23 | W2·R10 (AI theme resolver) | 📋 prompt ready | **after S25**; `destination_themes` per `AI_THEMING_SPEC.md` |
| S24 | P1 retention basics | ⬜ | |
| S25 | P1 share pages | ✅ merged | PR #23; preview-first `/j/[token]`; member count only |

In-flight fixes (merge before S17): `fix/join-deeplink-single-handler`
(reviewed, one nit: `ScaffoldMessenger.maybeOf`), `fix/web-share-and-lime-primary`.

Wave-1 slices S1–S14: shipped and verified (v0.1.0). Gate check after S22.
