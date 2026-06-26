# Spec Module

Parses and validates pipeline and target-project specs. This module should stay
pure: no network, no database, no Vamo product imports.

## Current Contract

- `parsePipelineSpec` validates source adapters, source license/policy flags,
  cursor strategy, mappings, and quality gates.
- `parseTargetProjectSpec` validates target adapters, shipment shape, and the
  server-side credential boundary.
- Validation returns structured errors with stable field paths for admin UI and
  API consumers.
