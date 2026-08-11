-- Converge identity-integrity summary privileges across environments with
-- explicit default grants. The original migration intentionally stays immutable.

do $$
begin
  if to_regprocedure('public.identity_integrity_summary()') is null then
    raise exception
      'identity_integrity_summary() must exist before privilege convergence';
  end if;
end;
$$;

revoke all on function public.identity_integrity_summary() from public;
revoke execute on function public.identity_integrity_summary() from anon;
revoke execute on function public.identity_integrity_summary() from authenticated;
grant execute on function public.identity_integrity_summary() to service_role;

do $$
begin
  if not has_function_privilege(
    'service_role',
    'public.identity_integrity_summary()',
    'execute'
  )
  or has_function_privilege(
    'anon',
    'public.identity_integrity_summary()',
    'execute'
  )
  or has_function_privilege(
    'authenticated',
    'public.identity_integrity_summary()',
    'execute'
  ) then
    raise exception 'identity_integrity_summary() privileges did not converge';
  end if;
end;
$$;
