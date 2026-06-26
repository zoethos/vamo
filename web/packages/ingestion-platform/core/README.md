# Core Module

Owns platform state machines and reusable runtime contracts: runs, tasks,
checkpoints, read models, shipment plans, leases, and command policy.

## Control Schema

`sql/control_schema.sql` is the platform-owned control-plane schema. It models
projects, specs, sources, targets, runs, tasks, leases, checkpoints, events,
dead letters, artifacts, policy evaluations, promotions, shipments, shipment
items, and audit log rows without importing Vamo product tables.

`sql/control_bootstrap_confluendo.sql` is the first managed-project bootstrap
companion. Run it after `control_schema.sql` in the Confluendo control project
to create the Vamo project row and grant the dashboard runtime role only its
current read/command permissions. The first-admin allowlist seed stays explicit
and email-scoped in the commented block.

The database smoke test runs only when `INGESTION_TEST_DATABASE_URL` points to a
disposable Postgres database.

## Fixture Runner

`src/pipeline-runner.ts` runs a local fixture batch through source reads, policy
evaluation, mapping transforms, staged candidates, dead letters, events, and an
in-memory checkpoint. It is the no-network proving path for worker behavior.
