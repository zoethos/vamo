// Provider-agnostic weather condition buckets. The client UI only ever sees a
// bucket, so swapping the upstream provider later is a server-only change.

export type ConditionBucket =
  | 'sunny'
  | 'cloudy'
  | 'rain'
  | 'thunderstorm'
  | 'snow'
  | 'fog'
  | 'unknown';

/// Maps an Open-Meteo WMO weather code to a condition bucket.
/// 0–1 clear/mainly clear · 2–3 partly cloudy/overcast · 45,48 fog ·
/// 51–67 drizzle/rain · 71–77 snow · 80–82 rain showers · 85,86 snow showers ·
/// 95–99 thunderstorm.
export function wmoToBucket(code: number | null | undefined): ConditionBucket {
  if (code == null || Number.isNaN(code)) return 'unknown';
  if (code <= 1) return 'sunny';
  if (code <= 3) return 'cloudy';
  if (code === 45 || code === 48) return 'fog';
  if (code >= 51 && code <= 67) return 'rain';
  if (code >= 71 && code <= 77) return 'snow';
  if (code >= 80 && code <= 82) return 'rain';
  if (code === 85 || code === 86) return 'snow';
  if (code >= 95 && code <= 99) return 'thunderstorm';
  return 'unknown';
}
