-- S20 fix — correct the FX fetch to exchangerate.host's CURRENT API.
-- (Provider unchanged — exchangerate.host, as decided. The 0019 path used the
--  OLD endpoint `/latest?base=` which 404s on the revamped apilayer API.)
--
-- Current API: GET /live?access_key=KEY&currencies=<CSV>
--   → { success, source, quotes: { "<SRC><CCY>": <ccy per 1 src>, ... } }
--
-- We rely on the default USD source (non-USD source is plan-gated in the
-- current docs), which still covers all currencies + any trip base by pivoting:
--   stored rate = base per 1 currency = quotes[USD+base] / quotes[USD+currency]
-- This matches the fxRateExpenseToBase convention; A4/Wave-1 snapshots untouched.
--
-- create-or-replace only; 0019 table/RLS/guards/writer/RPC unchanged. Key in
-- Vault (`exchangerate_access_key`) stays in use.

create or replace function _fetch_market_fx_rate(
  p_trip_base char(3),
  p_currency char(3)
) returns table(out_rate numeric, out_source text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_base char(3) := upper(trim(p_trip_base));
  v_cur  char(3) := upper(trim(p_currency));
  v_key  text;
  v_resp extensions.http_response;
  v_body jsonb;
  v_quotes jsonb;
  v_usd_per_base numeric;   -- base units per 1 USD
  v_usd_per_cur  numeric;   -- currency units per 1 USD
begin
  if v_cur = v_base then
    out_rate := 1;
    out_source := 'identity';
    return next;
    return;
  end if;

  v_key := coalesce(
    nullif(current_setting('app.exchangerate_access_key', true), ''),
    (select decrypted_secret from vault.decrypted_secrets
     where name = 'exchangerate_access_key' limit 1)
  );
  if v_key is null or v_key = '' then
    raise exception 'EXCHANGERATE_ACCESS_KEY not configured';
  end if;

  v_resp := extensions.http_get(
    'https://api.exchangerate.host/live?access_key=' || v_key
    || '&currencies='
    || (case when v_base = 'USD' then '' else v_base || ',' end) || v_cur
  );
  if v_resp.status <> 200 then
    raise exception 'fx upstream failed: %', v_resp.status;
  end if;

  v_body := v_resp.content::jsonb;
  if coalesce((v_body->>'success')::boolean, true) = false then
    raise exception 'fx upstream error';
  end if;

  v_quotes := v_body->'quotes';
  if v_quotes is null then
    raise exception 'fx upstream invalid';
  end if;

  -- USD per USD = 1; otherwise read quotes["USD"||CCY]
  v_usd_per_base := case when v_base = 'USD' then 1
                        else (v_quotes->>('USD' || v_base))::numeric end;
  v_usd_per_cur  := case when v_cur = 'USD' then 1
                        else (v_quotes->>('USD' || v_cur))::numeric end;

  if v_usd_per_base is null or v_usd_per_base <= 0 then
    raise exception 'unknown trip base currency %', v_base;
  end if;
  if v_usd_per_cur is null or v_usd_per_cur <= 0 then
    raise exception 'unknown currency %', v_cur;
  end if;

  -- base per 1 currency = (base per USD) / (currency per USD)
  out_rate := v_usd_per_base / v_usd_per_cur;
  out_source := 'exchangerate.host';
  return next;
end;
$$;

revoke all on function _fetch_market_fx_rate(char(3), char(3)) from public;
