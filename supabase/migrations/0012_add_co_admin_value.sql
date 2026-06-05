-- S16 / R1 — add co-admin enum value.
-- Must run in its own migration: PostgreSQL forbids using a new enum value
-- in the same transaction (SQLSTATE 55P04). See 0013_trip_roles.sql.

alter type member_role add value if not exists 'co-admin';
