# Vamo architecture documents

Architecture, provider-governance, and dependency-risk documents live here.

## Contents

| File | Purpose |
| --- | --- |
| `Vamo_Architecture.docx` | Founder-level architecture overview. |
| `DATA_ACQUISITION_STRATEGY.md` | **Canonical.** Place-data rights model, the three-layer acquisition funnel, Confluendo's role, and the load-bearing rules the architecture depends on. |
| `MUNICIPALITY_BASELINE_DELIVERY.md` | Proposed deterministic-partition delivery contract for the first municipality baseline. |
| `DATA_ACQUISITION_FUNNEL.svg` | **Canonical.** Source for the funnel diagram. |
| `Vamo_Data_Acquisition_Strategy.docx` | Generated export of `DATA_ACQUISITION_STRATEGY.md`. Do not edit. |
| `DATA_ACQUISITION_FUNNEL.png` | Generated export of `DATA_ACQUISITION_FUNNEL.svg`. Do not edit. |
| `ARCHITECTURE_BOUNDARIES.md` | Agent-facing architecture boundaries and extraction discipline. |
| `DEPENDENCIES.md` | Provider and package dependency register, blast radius, lock-in, and cost watch. |
| `PROVIDER_CONTROL_PLANE.md` | Provider registry/control-plane notes. |

Feature prompts may still mention older paths historically; new work should
link to this folder.

Where a document has both a canonical source and a generated export, edit the
source and regenerate — the exports are overwritten on every build:

```bash
npm install --no-save --package-lock=false docx@9.7.1 @resvg/resvg-js@2.6.2
```

```bash
node tool/docs/build_architecture_docx.mjs
```

Versions are pinned so an unchanged source cannot produce a different export
later. `--package-lock=false` keeps npm from leaving a `package-lock.json` in
the repo root, which is not gitignored.

**Regeneration is Windows-only for now.** The funnel diagram's layout is tuned
to Segoe UI metrics; that font ships only on Windows and is not redistributable,
so the generator pins the exact font files and disables system-font discovery.
It refuses to run elsewhere rather than silently substituting another face and
reflowing the diagram. Making this portable requires committing a bundled,
licensed font beside the SVG and re-tuning the layout — switching the stack to
Arial or Helvetica does not fix it, since neither is guaranteed on Linux either.

**CI does not run or validate the generator.** Nothing checks that the committed
`.docx` and `.png` still match their sources, and a binary shows no diff in
review. After regenerating, open the PNG and inspect it before committing.

Reusable platform docs live outside this Vamo architecture folder:

| Platform area | Purpose |
| --- | --- |
| `../platform/ingestion/` | Reusable ingestion/product-cache platform; Vamo is the first consumer target. |
