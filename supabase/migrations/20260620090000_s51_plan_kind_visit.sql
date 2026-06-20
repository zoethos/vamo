-- S51 — add 'visit' to plan_item_kind (C-light's first new kind).
--
-- STANDALONE migration: a new enum value cannot be used (seeds, checks, RPCs)
-- in the same transaction that adds it. Capability seed + any use live in the
-- separate follow-up migration 20260620090100_s51_visit_capabilities.sql.
-- Nothing else belongs in this file.

alter type plan_item_kind add value if not exists 'visit';
