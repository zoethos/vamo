# Workflows — processes that need diagrams

Delicate multi-actor processes get documented here **before** implementation:
a state/sequence diagram (Mermaid — renders on GitHub), the invariants the
diagram must preserve, and a pointer to the deciding design doc. If a process
has a non-obvious failure mode that bit us once, it earns a page here so it
never bites twice.

Conventions:

- One file per process, kebab-case, named for the process not the slice.
- Mermaid only (no binary images) — diffable, reviewable, GitHub-rendered.
- Each page links its constitution/design source and the slice that
  implements it. The diagram is the contract; code reviews check against it.
- Update the diagram in the same PR that changes the behavior.

| Workflow | Status | Source of truth | Slice |
|---|---|---|---|
| [Trip closure (deemed acceptance)](trip-closure.md) | Decided 2026-06-05 | `docs/design/MONEY_GOVERNANCE.md` D2 + `docs/design/CLOSURE_PATTERNS.md` | S17 |
| [Expense + share consent lifecycle](expense-consent.md) | Diagrammed 2026-06-05 | `docs/design/MONEY_GOVERNANCE.md` D1 + A1 | S19 |
| Auth deep link (single-PKCE waiting room) | TODO (backfill — bit us twice) | `app_core` auth docs / commit history | W1 |
| Invite join (QR / link / push routes) | TODO (backfill — GoException lesson) | `fix/join-deeplink-single-handler` | S15/S16 |
| Scheduled jobs + CRON_SECRET auth | TODO | `docs/SCHEDULED_JOBS.md` | S16/S17 |
