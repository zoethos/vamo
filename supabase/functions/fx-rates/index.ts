// Slice 6 — FX proxy: always fetches EUR pivot from exchangerate.host, rebases to ?base=.
// Deploy: supabase secrets set EXCHANGERATE_ACCESS_KEY=your_key
//         supabase functions deploy fx-rates
// Client: FX_RATES_FUNCTION_URL + same key in app/.env for direct fallback.

const HOST = 'https://api.exchangerate.host/latest';
const PIVOT = 'EUR';

// Best-effort only — isolates are recycled; do not rely on this for daily caching.
let memoryCache: { body: Record<string, unknown>; at: number } | null = null;
const MEMORY_CACHE_MS = 60 * 60 * 1000; // 1h within a warm isolate

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, content-type',
      },
    });
  }

  const accessKey = Deno.env.get('EXCHANGERATE_ACCESS_KEY')?.trim();
  if (!accessKey) {
    return json(
      { error: 'missing_access_key', message: 'Set EXCHANGERATE_ACCESS_KEY secret' },
      503,
    );
  }

  const url = new URL(req.url);
  const tripBase = (url.searchParams.get('base') ?? PIVOT).toUpperCase();

  const now = Date.now();
  let pivotBody: Record<string, unknown>;

  if (memoryCache && now - memoryCache.at < MEMORY_CACHE_MS) {
    pivotBody = memoryCache.body;
  } else {
    const upstreamUrl = `${HOST}?access_key=${encodeURIComponent(accessKey)}&base=${PIVOT}`;
    const upstream = await fetch(upstreamUrl);
    if (!upstream.ok) {
      return json({ error: 'upstream_failed', status: upstream.status }, 502);
    }

    const data = await upstream.json();
    if (data.success === false) {
      return json(
        { error: 'upstream_error', detail: data.error ?? data },
        502,
      );
    }
    if (!data.rates || typeof data.rates !== 'object') {
      return json({ error: 'invalid_upstream' }, 502);
    }

    pivotBody = {
      base: PIVOT,
      date: data.date ?? new Date().toISOString().slice(0, 10),
      rates: data.rates as Record<string, number>,
      fetched_at: new Date().toISOString(),
    };
    memoryCache = { body: pivotBody, at: now };
  }

  const rates = pivotBody.rates as Record<string, number>;
  const rebased = rebaseRates(rates, tripBase);
  if (!rebased) {
    return json({ error: 'unknown_base', base: tripBase }, 400);
  }

  return json({
    base: tripBase,
    date: pivotBody.date,
    rates: rebased,
    fetched_at: pivotBody.fetched_at,
    pivot: PIVOT,
  });
});

function rebaseRates(
  pivotRates: Record<string, number>,
  tripBase: string,
): Record<string, number> | null {
  const divisor = pivotRates[tripBase];
  if (divisor == null || divisor <= 0) return null;

  const out: Record<string, number> = { [tripBase]: 1 };
  for (const [code, value] of Object.entries(pivotRates)) {
    if (value > 0) out[code] = value / divisor;
  }
  return out;
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'public, max-age=3600',
    },
  });
}
