-- S50 RPC compatibility:
-- The old S17 propose_expense overload conflicts with the S50 signature because
-- PostgREST cannot choose between it and the new function with defaulted FX args.
-- Dropping the obsolete overload lets old-style calls resolve to the S50 RPC.

drop function if exists propose_expense(
  uuid, uuid, uuid, bigint, char, bigint, numeric, text, text, timestamptz
);
