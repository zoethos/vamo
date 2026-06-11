# Slice tracker — Wave 2 (the real stage)

Living status; specs stay sealed. Conventions: `docs/CONVENTIONS.md`.
Updated: 2026-06-11.

## Recommended sequencing (founder-approved)

1. **S25 is live** — PR #23 merged, Supabase `0026_s25_get_trip_preview` applied,
   Vercel `NEXT_PUBLIC_SUPABASE_URL` + publishable key set, and `/j/<token>`
   smoke verified on production.
2. **S30 active** — video capture is being implemented on
   `feature/capture-video` on top of the S46 notification branch. The current app
   already uses the S44/S45 carousel add surface, so S30 wires video into that
   surface rather than resurrecting the older Capture-FAB sheet.
3. **S22 held** — PR #20 remains blocked on the device + cron dry-run gate. Before
   resuming, rebase it and move its current `0025_s22_close_notice.sql` to the
   next free migration ordinal, because production already has S25 as `0026`.
4. **Internal build** — resume Play/internal tester work around whichever slice
   is actively being shipped.

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
| S21 | W2·R8 (EventList) | ✅ merged (`1ba8a9e`) | EventList + RSVP + realtime (0022–0024: parent-touch, clear RPC, cascade guard); plan-propagation hardening incl. autoDispose binding + flush-before-RSVP (`84b3620`); UI fixes (back-nav fallback, tab-aware FAB, no dup Plan CTA). smoke 76/76 |
| — | **Wave 2 internal build (S15–S20)** | 🔶 in progress | S16 verified; **release-signed `.aab` built** (upload key CN=Tiziano Rocca/Vamo, R8 proguard fix for ML Kit Latin-only). Next: Play internal upload → app-signing-key SHA-256 → assetlinks → testers (`SHIP_INTERNAL.md` 5–8) |
| — | **Notifications subsystem** | 🔭 W3 pillar (`design/NOTIFICATIONS.md`) | adopted as destination; lifecycle/nudge/RSVP/dispute become producers; ops alerts separate |
| S22 | W2·R7 (close report) + P1 nudge | 🔶 PR #20 held | device + cron gate before merge; cron unscheduled; **renumber migration on rebase** (old PR slot `0025`, prod frontier includes S25 `0026`) |
| S23 | W2·R10 (AI theme resolver) | ✅ merged (`47d0c9b2`) | provider-neutral adapter, default OpenAI; `destination_themes` per `AI_THEMING_SPEC.md` |
| S24 | P1 retention basics | ⬜ | |
| S25 | P1 share pages | ✅ live | PR #23; preview-first `/j/[token]`; member count only; production smoke verified after Vercel publishable key fix |
| S26 | Contact invite (growth) | ✅ merged (`1c6ed4b`) | permissionless selected contact invite; no `READ_CONTACTS`; uses S25 `/j/<token>` + `ch=contact`; device-pass debt remains before tester confidence |
| S27 | Mobile UI polish I | ✅ merged (`bd20a0ab`) | tester-readiness polish + Linux golden stabilization; `s27_polish_golden_test.dart` present |
| S29 | Design system foundation | 📋 backlog (`S29_DESIGN_SYSTEM_FOUNDATION_PROMPT.md`) | token/component substrate for deeper polish; parked until founder/design direction |
| S30 | Capture video | 🔶 branch in progress (`feature/capture-video`) | `0032_trip_videos`, Drift v17, `CaptureChoiceSheet` Video action, Memories video grid, in-app `video_player` playback; device picker/playback gate pending |
| S46 | Notifications primitive + inbox | 🔶 branch ready (`feature/notification-center`) | record-first notification table/RPC, lifecycle job decoupled from push, Drift pull sync, bell badge + inbox. CI + cloud RLS smoke green; `trip-lifecycle-jobs` and `send-push` deployed. Remaining gates: guarded manual lifecycle invoke and 2-device no-push/push verification before enabling cron. |

Wave-1 slices S1–S14: shipped and verified (v0.1.0). Gate check after S22.
