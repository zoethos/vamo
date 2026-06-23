-- Foursquare Places API pricing changed in June 2026: keep Vamo's global
-- safety cap inside the free Pro-call allowance unless deliberately raised
-- after reviewing current billing terms.
update public.provider_config
set monthly_free_cap = 500,
    updated_at = now()
where service = 'poi'
  and provider = 'foursquare'
  and monthly_free_cap > 500;
