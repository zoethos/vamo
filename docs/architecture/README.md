# Vamo architecture documents

Architecture, provider-governance, and dependency-risk documents live here.

## Contents

| File | Purpose |
| --- | --- |
| `Vamo_Architecture.docx` | Founder-level architecture overview. |
| `Vamo_Data_Acquisition_Strategy.docx` | Place-data rights model, the three-layer acquisition funnel, Confluendo's role, and the load-bearing rules the architecture depends on. |
| `DATA_ACQUISITION_FUNNEL.png` | Funnel diagram from the acquisition strategy (source of truth for the three rights classes). |
| `ARCHITECTURE_BOUNDARIES.md` | Agent-facing architecture boundaries and extraction discipline. |
| `DEPENDENCIES.md` | Provider and package dependency register, blast radius, lock-in, and cost watch. |
| `PROVIDER_CONTROL_PLANE.md` | Provider registry/control-plane notes. |

Feature prompts may still mention older paths historically; new work should
link to this folder.

Reusable platform docs live outside this Vamo architecture folder:

| Platform area | Purpose |
| --- | --- |
| `../platform/ingestion/` | Reusable ingestion/product-cache platform; Vamo is the first consumer target. |
