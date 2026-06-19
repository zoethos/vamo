-- S48 fix — lock _enter_soft_close to service_role only (explicit role revokes).

revoke all on function _enter_soft_close(uuid) from public;
revoke all on function _enter_soft_close(uuid) from anon;
revoke all on function _enter_soft_close(uuid) from authenticated;
grant execute on function _enter_soft_close(uuid) to service_role;
