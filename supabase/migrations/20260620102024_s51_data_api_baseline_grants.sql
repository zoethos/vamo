-- S51 follow-up: make the Supabase Data API privilege layer explicit.
--
-- Some projects are created with "Automatically expose new tables" disabled.
-- In that shape, RLS policies are never reached because anon/authenticated lack
-- base table privileges. Grant access to the current public tables only when RLS
-- is enabled; RLS remains the source of truth for row/action authorization.

grant usage on schema public to anon, authenticated;

do $$
declare
  v_table regclass;
begin
  for v_table in
    select c.oid::regclass
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and c.relrowsecurity
    order by c.relname
  loop
    execute format(
      'grant select, insert, update, delete on table %s to anon, authenticated',
      v_table
    );
  end loop;
end $$;

grant usage, select on all sequences in schema public to anon, authenticated;
