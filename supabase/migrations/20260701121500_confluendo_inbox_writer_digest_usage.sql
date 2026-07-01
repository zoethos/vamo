-- Allow the least-privilege Confluendo inbox writer to compute checksums in
-- Vamo Postgres using the same pgcrypto function that Vamo's apply function
-- later uses to verify them.
--
-- The writer still has no privileges on public product tables and no RLS
-- bypass; this only permits resolving `extensions.digest(...)` while writing
-- confluendo_inbox package rows.

grant usage on schema extensions to confluendo_inbox_writer;
