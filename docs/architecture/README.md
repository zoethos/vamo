# Vamo architecture documents

Architecture, provider-governance, and dependency-risk documents live here.

## Contents

| File | Purpose |
| --- | --- |
| `Vamo_Architecture.docx` | Founder-level architecture overview. |
| `DATA_ACQUISITION_STRATEGY.md` | **Canonical.** Place-data rights model, the three-layer acquisition funnel, Confluendo's role, and the load-bearing rules the architecture depends on. |
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
npm install --no-save docx @resvg/resvg-js && node tool/docs/build_architecture_docx.mjs
```

Reusable platform docs live outside this Vamo architecture folder:

| Platform area | Purpose |
| --- | --- |
| `../platform/ingestion/` | Reusable ingestion/product-cache platform; Vamo is the first consumer target. |
