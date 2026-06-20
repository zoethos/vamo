-- S51 follow-up: make service_role table privileges explicit.
--
-- The service_role bypasses RLS, but on projects created with restrictive Data
-- API/table defaults it still needs base table privileges for smoke helpers,
-- jobs, and SECURITY DEFINER orchestration that use the service key.

grant usage on schema public to service_role;
grant all privileges on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
