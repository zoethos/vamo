# UX/UI Review — Triage & Integration Cost

**Source:** Design review (Claude), 2026-06-20. Raw review + annotated mockups:
[`assets/ux-review-2026-06/`](assets/ux-review-2026-06/) (`UX_REVIEW_RAW.md` + `00–06-*.png`).
**Status:** triaged 2026-06-20. The raw review is the hypothesis set; this file is the cost-mapped
plan against the current state (mid-Cycle-3 S51, Cycle 2 launch gates open, pre-closed-beta).

The review is high quality and codebase-grounded — keep and schedule it, don't action it as one blob.
It spans three cost classes: cheap front-end polish, a global nav/platform refactor, and net-new
Wave-3 surfaces. One item (custom split) is a money-model change in disguise.

## Integration-cost map

| Item | True nature | Cost | Bucket |
|---|---|---|---|
| **H1** 5-slot nav + lime FAB | Global shell refactor (4→5 slot, retire app-bar "+", every tab's add affordance). Fold in **M2** (M3 `NavigationBar`, edge-to-edge, predictive back, Credential Manager) + **M3** (hero `SliverAppBar` refactor). Golden churn → regen on Linux. | Medium, cross-cutting FE | Cycle 4 |
| **H2** keypad + pinned CTA + fix read-only split + smart defaults | Front-end; fixes real defects (read-only `InputDecorator` split, off-screen Save CTA, `flow_abandoned`). | Medium FE | Cycle 4 (cheap subset optional pre-beta) |
| **H2 (custom split)** | ⚠️ **Not front-end — a money-model change.** Conflicts with the S50 hardening: `insert_committed_expense` recomputes **equal** split server-side, `_resplit` assumes equal, the share-sum invariant. Custom shares ⇒ new RPC params + server validation + sync + characterization tests. | **Large + product decision** | Separate money slice |
| **H3** balances donut head + single Settle CTA | Front-end over the existing (excellent, unchanged) settle engine. | Small–Med FE | Cycle 4 |
| **H4** Trip Map / journey replay | Net-new flagship surface; already **roadmap Wave 3**. Data hooks exist (EXIF lat/lng/time, expense places). | Large | Post-beta (Wave 3) |
| **H5** Trip Wrapped | Net-new recap-story surface; **roadmap Wave 3**. Highest-emotion share / retention hook. | Large | Post-beta (Wave 3) |
| **M1** global vs per-trip dedup | IA refactor — tabs become aggregators that drill into per-trip views. | Medium | Cycle 4 |
| **M4** profile structure · **M5** auth warm-up + real wordmark · **L1–L4** | Cheap polish. M5 = biggest first-impression delta per effort. | Small each | Cycle 4 (M5 optional pre-beta) |
| **L5** snapshot share theming | Ties to Wave-2 theme packs; seeds the growth loop; feeds H5. | Small–Med | With Wave-2 themes |

## Sequencing — mostly *later*, nothing blocks closed beta

1. **Stay on the critical path now:** finish **S51 (Visit/POI)** → clear the **Cycle 2 gates**
   ([`LAUNCH_GATES.md`](../LAUNCH_GATES.md)) → **closed beta on the current UX.** The current build is
   good enough for testers' hands.
2. **Let the beta validate this backlog.** These are well-argued hypotheses (is `flow_abandoned`
   actually high? is the non-editable split a real complaint?). Spend the FE budget on confirmed
   friction.
3. **"Cycle 4 UX pass" before wider/public launch:** H1(+M2+M3), H3, M4, M5, M1, L1–L4 — one coherent
   front-end pass that makes the app read like the brand boards.
4. **Wave 3 (post-beta):** H4 Trip Map, H5 Wrapped, web share pages, L5. Don't pull flagship surfaces
   forward — they'd compete with Cycle 3 D/E.
5. **Money decision required:** H2 custom split — decide whether v1 even wants custom splits (equal-only
   matches the audience *and* the hardened money path) before building.

**Optional cheap pre-beta pull-forwards** (first-impression wins, no model change): **M5** real wordmark
on Auth; **H2** read-only-split fix + pinned CTA.

## Validated — keep as-is (per the review)
Minimal-transaction settle engine; "Vamo never moves money" deep-link model; sanitized-error policy;
solo trips hiding Balances; fake-door signal stack; contrast governance (goLime fill-only, coralText for
small text). Color rule: lime `#C6FF00` = the single primary action per screen, never decorative.

## Open questions (owner: product)
1. Trip Map / Wrapped — ship Wave-3 concepts, or polished "coming soon" fake doors to measure intent first?
2. FAB "+" mapping per tab (expense vs trip; behavior on Profile).
3. Global vs per-trip (M1) — pure aggregators, or retain standalone create affordances?
4. Material You — fully override dynamic color with the locked palette (recommended)?
5. Web share pages (view-before-install) — in/out for near term?
6. Wrapped data — are distance + photo counts reliable at close for the first cut, or gate some frames?
