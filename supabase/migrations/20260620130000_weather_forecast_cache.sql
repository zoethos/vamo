-- H-P0 — server-side weather forecast cache.
-- Written/read only by the weather-forecast edge function via the service role;
-- clients never touch it directly (they call the function). RLS on + no policies
-- + revoked grants => authenticated/anon cannot read it; service_role bypasses RLS.

create table if not exists public.weather_forecast_cache (
  destination_key text not null,
  forecast_date   date not null,
  bucket          text not null
    check (bucket in ('sunny','cloudy','rain','thunderstorm','snow','fog','unknown')),
  temp_high       numeric,
  temp_low        numeric,
  fetched_at      timestamptz not null default now(),
  primary key (destination_key, forecast_date)
);

comment on table public.weather_forecast_cache is
  'H-P0: cached Open-Meteo previews keyed by (lowercased destination, start date). ~6h TTL, refreshed by the weather-forecast edge function.';

alter table public.weather_forecast_cache enable row level security;

revoke all on public.weather_forecast_cache from anon, authenticated;
