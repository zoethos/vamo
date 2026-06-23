// OpenRouteService road-distance adapter (Slice 4.1). Best-effort enhancement
// over the straight-line haversine feasibility: real road km for a coord pair.
// Pure helpers are unit-tested; only `orsMatrixMeters` touches the network.

import type { Coord, TravelMode } from "./draft.ts";

export interface RoutingConfig {
  provider: string;
  adapter: "ors-matrix";
  apiKey: string;
  baseUrl: string;
  timeoutMs: number;
}

export class RoutingError extends Error {
  constructor(kind: string, detail: Record<string, unknown> = {}) {
    super(kind);
    this.kind = kind;
    this.detail = detail;
  }
  kind: string;
  detail: Record<string, unknown>;
}

/** ORS routing profile for a mode, or null for non-road modes (train/flight). */
export function orsProfileForMode(mode: TravelMode): string | null {
  switch (mode) {
    case "car":
    case "motorbike":
    case "bus":
      return "driving-car";
    case "bike":
      return "cycling-regular";
    case "train":
    case "flight":
      return null;
  }
}

/** Stable cache key for a (from, to, profile) pair (~11 m coordinate precision). */
export function pairCacheKey(from: Coord, to: Coord, profile: string): string {
  const r = (n: number) => n.toFixed(4);
  return `${profile}|${r(from.lat)},${r(from.lng)}|${r(to.lat)},${r(to.lng)}`;
}

export function loadRoutingConfig(args: {
  provider: string | undefined;
  config: Record<string, unknown> | undefined;
}): RoutingConfig {
  const provider = (args.provider ?? "openrouteservice").trim().toLowerCase();
  const config = args.config ?? {};
  const adapter = stringFromConfig(config, "adapter") ?? "ors-matrix";
  if (provider !== "openrouteservice" || adapter !== "ors-matrix") {
    throw new RoutingError("unsupported_routing_provider", {
      provider,
      adapter,
    });
  }
  return {
    provider,
    adapter: "ors-matrix",
    apiKey: firstEnvValue([
      "VAMO_OPENROUTESERVICE_API_KEY",
      "VAMO_OPENROUTESERVICE_PROD_API_KEY",
      "VAMO_OPENROUTESERVICE_STAGING_API_KEY",
    ]),
    baseUrl: ensureTrailingSlash(
      stringFromConfig(config, "base_url") ??
        "https://api.openrouteservice.org/",
    ),
    timeoutMs: numberFromConfig(config, "timeout_ms") ?? 8000,
  };
}

/** Parse an ORS matrix response into a source->dest distance matrix (metres). */
export function parseOrsDistances(
  payload: unknown,
): (number | null)[][] | null {
  if (!payload || typeof payload !== "object") return null;
  const distances = (payload as Record<string, unknown>).distances;
  if (!Array.isArray(distances)) return null;
  return distances.map((row) =>
    Array.isArray(row)
      ? row.map((v) => typeof v === "number" && Number.isFinite(v) ? v : null)
      : []
  );
}

/** Distinct coords (by ~11 m key) with an index lookup for matrix addressing. */
export function indexCoords(
  coords: Coord[],
): { unique: Coord[]; indexOf: (c: Coord) => number } {
  const key = (c: Coord) => `${c.lat.toFixed(4)},${c.lng.toFixed(4)}`;
  const map = new Map<string, number>();
  const unique: Coord[] = [];
  for (const c of coords) {
    const k = key(c);
    if (!map.has(k)) {
      map.set(k, unique.length);
      unique.push(c);
    }
  }
  return { unique, indexOf: (c) => map.get(key(c)) ?? -1 };
}

/** One ORS matrix call for a single profile; returns metres source->dest. */
export async function orsMatrixMeters(
  config: RoutingConfig,
  profile: string,
  coords: Coord[],
): Promise<(number | null)[][]> {
  if (!config.apiKey) throw new RoutingError("provider_unconfigured");
  const endpoint = new URL(`v2/matrix/${profile}`, config.baseUrl).toString();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.timeoutMs);
  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: config.apiKey,
      },
      signal: controller.signal,
      body: JSON.stringify({
        locations: coords.map((c) => [c.lng, c.lat]),
        metrics: ["distance"],
        units: "m",
      }),
    });
    if (!response.ok) {
      throw new RoutingError(
        response.status === 429
          ? "throttled"
          : response.status >= 500
          ? "provider_5xx"
          : "provider_4xx",
        { provider_status: response.status },
      );
    }
    const parsed = parseOrsDistances(await response.json());
    if (!parsed) throw new RoutingError("invalid_output");
    return parsed;
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new RoutingError("timeout");
    }
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

function stringFromConfig(
  config: Record<string, unknown>,
  key: string,
): string | undefined {
  const value = config[key];
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : undefined;
}

function numberFromConfig(
  config: Record<string, unknown>,
  key: string,
): number | undefined {
  const value = config[key];
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

function ensureTrailingSlash(value: string): string {
  if (!value) return "";
  return value.endsWith("/") ? value : `${value}/`;
}

function firstEnvValue(names: string[]): string {
  for (const name of names) {
    const value = Deno.env.get(name)?.trim();
    if (value) return value;
  }
  return "";
}
