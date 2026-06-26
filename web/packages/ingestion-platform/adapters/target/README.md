# Target Adapters

Target adapters inspect and ship to consumer projects. First-class targets are
Postgres and Supabase/Postgres. Target credentials must remain server-side.

`postgres-dry-run` connects only from a server-side runtime, introspects target
tables, and emits a shipment plan with inserts, updates, no-ops, and
incompatibilities. It does not write to the target database.

`supabase-postgres` wraps the Postgres dry-run path with Supabase-specific
guards for service-role isolation, dry-run-only posture, exposed-table RLS, and
optional explicit Data API grants. It also does not write to the target
database.
