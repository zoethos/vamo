-- S48 — soft-close lifecycle enum value (must be its own migration).
-- PostgreSQL forbids using a new enum literal in the same transaction (55P04).

alter type trip_lifecycle add value if not exists 'soft_closed';
