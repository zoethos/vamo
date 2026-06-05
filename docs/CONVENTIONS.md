# Doc numbering conventions (registry)

One meaning per prefix, repo-wide. When referencing across docs, qualify
wave-scoped IDs (e.g. `W2·R3`); inside their home doc the bare ID is fine.

| Prefix | Meaning | Scope | Home doc |
|---|---|---|---|
| `R#` | Requirement (the WHAT) | per wave — restarts each spec | `Vamo_WaveN_Spec.md` §5 |
| `S#` | Implementation slice (the WHEN) | **global monotonic** across waves (S1… never resets) | spec §8 + `docs/slices/` |
| `D#` | Design decision | per design memo | `docs/design/*.md` |
| `A#` | Amendment/refinement to a decided memo | per design memo | `docs/design/*.md` (e.g. MONEY_GOVERNANCE A1–A6) |
| `P0/P1/P2` | Priority class only — never an item ID | spec §5 | specs |
| `P#` | Pattern (research memos only, local) | per memo | e.g. `CLOSURE_PATTERNS.md` |
| `[AI-IDEA]` | Proposal tag | global | `AI_IDEATION_GOVERNANCE.md` ledger |

**Retired prefixes** (do not use in new text; map on touch):
- `T#` (Wave-1 task numbering, e.g. T10.5 = push plumbing → S16)
- `W2-#` (seed work items → absorbed into S15–S25)

Rules:
1. A slice page (`docs/slices/SXX_PROMPT.md`) names the R# it implements in
   its header; the tracker (`docs/slices/README.md`) is the only place
   status lives — specs stay sealed, trackers stay current.
2. Workflow diagrams (`docs/workflows/`) reference D#/A# as contract sources.
3. New prefix = new row here, in the same PR.
