# Core Module

Owns platform state machines and reusable runtime contracts: runs, tasks,
checkpoints, read models, shipment plans, leases, and command policy.

## Control Schema

`sql/control_schema.sql` is the platform-owned control-plane schema. It models
projects, specs, sources, targets, runs, tasks, leases, checkpoints, events,
dead letters, artifacts, policy evaluations, promotions, shipments, shipment
items, and audit log rows without importing Vamo product tables.

The database smoke test runs only when `INGESTION_TEST_DATABASE_URL` points to a
disposable Postgres database.

## Fixture Runner

`src/pipeline-runner.ts` runs a local fixture batch through source reads, policy
evaluation, mapping transforms, staged candidates, dead letters, events, and an
in-memory checkpoint. It is the no-network proving path for worker behavior.
