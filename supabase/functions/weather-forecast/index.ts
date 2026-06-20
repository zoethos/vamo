// H-P0 — weather-forecast gateway.
// Input: trip_id (query ?trip_id= or JSON body). Resolves the trip via the
// caller's JWT (RLS = member-only), reads destination/name + start_date
// server-side, then geocodes + forecasts via Open-Meteo and returns a
// provider-agnostic condition bucket for the trip's start date. Caches by
// (location label, date).
//
// Prototype provider: Open-Meteo (free, no key, non-commercial). Swap to a
// licensed provider before public scale — gateway + buckets make it server-only.
//
// Deploy: supabase functions deploy weather-forecast
// (uses the platform-provided SUPABASE_URL / SUPABASE_ANON_KEY /
//  SUPABASE_SERVICE_ROLE_KEY secrets — no extra key for Open-Meteo.)

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { wmoToBucket } from './condition_bucket.ts';

const GEOCODE = 'https://geocoding-api.open-meteo.com/v1/search';
const FORECAST = 'https://api.open-meteo.com/v1/forecast';
const CACHE_TTL_MS = 6 * 60 * 60 * 1000; // 6h

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, content-type',
      },
    });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'unauthorized' }, 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: 'misconfigured' }, 503);
  }

  // User-scoped client: RLS makes the trip visible only to its members.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData } = await userClient.auth.getUser();
  if (!authData?.user) return json({ error: 'unauthorized' }, 401);

  const tripId = await readTripId(req);
  if (!tripId) return json({ error: 'missing_trip_id' }, 400);

  const { data: trip, error } = await userClient
    .from('trips')
    .select('id, name, destination, start_date')
    .eq('id', tripId)
    .maybeSingle();
  if (error || !trip) return json({ error: 'trip_not_found' }, 404);

  const destination = String(trip.destination ?? '').trim();
  const name = String(trip.name ?? '').trim();
  const locationLabel = destination.length > 0 ? destination : name;
  const startDate = trip.start_date as string | null;
  if (!locationLabel || !startDate) {
    return json({ available: false, reason: 'no_location_or_date' });
  }

  const serviceClient = createClient(supabaseUrl, serviceKey);
  const destinationKey = locationLabel.toLowerCase();

  // 1) cache
  const { data: cached } = await serviceClient
    .from('weather_forecast_cache')
    .select('bucket, temp_high, temp_low, fetched_at')
    .eq('destination_key', destinationKey)
    .eq('forecast_date', startDate)
    .maybeSingle();
  if (cached && Date.now() - Date.parse(cached.fetched_at) < CACHE_TTL_MS) {
    return json(preview(cached.bucket, cached.temp_high, cached.temp_low, startDate));
  }

  // 2) geocode (Open-Meteo)
  const place = await firstGeocodeResult(locationLabel);
  if (!place) return json({ available: false, reason: 'geocode_failed' });

  // 3) forecast for the start date
  const daily = await dailyForecast(place.latitude, place.longitude, startDate);
  if (!daily) return json({ available: false, reason: 'forecast_unavailable' });

  const bucket = wmoToBucket(daily.code);
  await serviceClient.from('weather_forecast_cache').upsert(
    {
      destination_key: destinationKey,
      forecast_date: startDate,
      bucket,
      temp_high: daily.tempHigh,
      temp_low: daily.tempLow,
      fetched_at: new Date().toISOString(),
    },
    { onConflict: 'destination_key,forecast_date' },
  );

  return json(preview(bucket, daily.tempHigh, daily.tempLow, startDate));
});

async function readTripId(req: Request): Promise<string | null> {
  const q = new URL(req.url).searchParams.get('trip_id');
  if (q) return q;
  try {
    const body = await req.json();
    const v = body?.trip_id;
    return typeof v === 'string' && v.length > 0 ? v : null;
  } catch (_) {
    return null;
  }
}

async function firstGeocodeResult(
  name: string,
): Promise<{ latitude: number; longitude: number } | null> {
  try {
    const res = await fetch(
      `${GEOCODE}?name=${encodeURIComponent(name)}&count=1&format=json`,
    );
    if (!res.ok) return null;
    const data = await res.json();
    const r = data?.results?.[0];
    if (r == null || typeof r.latitude !== 'number') return null;
    return { latitude: r.latitude, longitude: r.longitude };
  } catch (_) {
    return null;
  }
}

async function dailyForecast(
  lat: number,
  lng: number,
  date: string,
): Promise<{ code: number; tempHigh: number | null; tempLow: number | null } | null> {
  try {
    const url = `${FORECAST}?latitude=${lat}&longitude=${lng}` +
      `&daily=weathercode,temperature_2m_max,temperature_2m_min` +
      `&start_date=${date}&end_date=${date}&timezone=auto`;
    const res = await fetch(url);
    if (!res.ok) return null;
    const d = (await res.json())?.daily;
    const code = d?.weathercode?.[0];
    if (code == null) return null;
    return {
      code,
      tempHigh: d?.temperature_2m_max?.[0] ?? null,
      tempLow: d?.temperature_2m_min?.[0] ?? null,
    };
  } catch (_) {
    return null;
  }
}

function preview(
  bucket: string,
  tempHigh: number | null,
  tempLow: number | null,
  date: string,
) {
  return { available: true, bucket, temp_high: tempHigh, temp_low: tempLow, date };
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}
