// Slice 2 — Advanced Travel Planning: draft a valid Plan from leg constraints.
// Deploy: supabase functions deploy draft-trip-route
//
// Secrets/config:
//   VAMO_OPENAI_STAGING_API_KEY=...               (staging project)
//   VAMO_OPENAI_PROD_API_KEY=...                  (production project)
//   VAMO_OPENAI_API_KEY=...                       (optional shared alias)
//   VAMO_ROUTE_DRAFT_AZURE_OPENAI_API_KEY=...     (optional, when enabled)
// Provider/model/base URL/routing live in provider_config, not in app clients.
//
// Requires Authorization: Bearer <user JWT>. Sends only the constraint envelope
// (destination, dates, modes, reach) — never trip names, members, or money.
// Proposes a draft only: NO Plan writes here (commit is Slice 3).

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  completeServiceUsageReservation,
  recordPremiumGateNotification,
  releaseServiceUsageReservation,
  reserveServiceUsage,
} from "../_shared/premium.ts";
import {
  type DraftInput,
  parseDraftInput,
  validateRouteDraft,
} from "./draft.ts";
import {
  generateRouteDraft,
  loadRouteAiProviderConfig,
  ProviderError,
  providerErrorMetadata,
  type RouteAiProviderConfig,
} from "./providers.ts";

type JsonRecord = Record<string, unknown>;
type SupabaseClientLike = ReturnType<typeof createClient<any, "public", any>>;

const SERVICE = "draft-trip-route";
const DEFAULT_TIMEOUT_MS = 30_000;
const DEFAULT_MAX_TOKENS = 1400;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const env = loadSupabaseEnv();
  if (!env) return json({ ok: false, error: "missing_supabase_env" }, 500);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }
  const jwt = authHeader.slice("Bearer ".length);
  const userClient = createClient(env.url, env.anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const serviceClient = createClient(env.url, env.serviceKey);

  const { data: userData, error: userError } = await userClient.auth.getUser(
    jwt,
  );
  if (userError || !userData.user) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }
  const userId = userData.user.id;

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  const parsed = parseDraftInput(body);
  if ("error" in parsed) return json({ ok: false, error: parsed.error }, 400);
  const input = parsed.input;

  const isMember = await verifyActiveMember(
    serviceClient,
    input.tripId,
    userId,
  );
  if (!isMember) return json({ ok: false, error: "forbidden" }, 403);

  const cacheKey = await sha256Hex(envelopeFingerprint(input));

  // Cache first — a reusable draft for an identical envelope is free.
  const cached = await readCache(serviceClient, cacheKey);
  if (cached) {
    await recordUsage(serviceClient, {
      provider: cached.provider ?? "cache",
      model: cached.model ?? undefined,
      status: "success",
      cached: true,
      metadata: { cache_key: cacheKey },
    });
    return json({
      ok: true,
      status: "success",
      cached: true,
      draft: cached.draft,
    });
  }

  // Fresh draft — reserve quota (and gate) before spending the provider.
  let reservation;
  try {
    reservation = await reserveServiceUsage(serviceClient, {
      idempotencyKey: crypto.randomUUID(),
      service: SERVICE,
      userId,
    });
  } catch (_e) {
    return json({ ok: false, error: "reservation_failed" }, 500);
  }
  if (reservation.gated || !reservation.reserved) {
    await recordPremiumGateNotification(serviceClient, {
      userId,
      service: SERVICE,
      reason: reservation.reason ?? "quota_exceeded",
    }).catch(() => {});
    await recordUsage(serviceClient, {
      provider: reservation.provider ?? "unreserved",
      status: "throttled",
      cached: false,
      errorKind: reservation.reason ?? "gated",
      metadata: { cache_key: cacheKey },
    });
    return json({
      ok: false,
      status: "gated",
      gated: true,
      reason: reservation.reason ?? "quota_exceeded",
    });
  }

  let config: RouteAiProviderConfig;
  try {
    config = loadRouteAiProviderConfig({
      provider: reservation.provider,
      config: reservation.config,
    });
  } catch (e) {
    const errorKind = classifyProviderError(e);
    await releaseServiceUsageReservation(
      serviceClient,
      reservation.reservationId,
    )
      .catch(() => {});
    await recordUsage(serviceClient, {
      provider: reservation.provider ?? "unsupported",
      status: "fallback",
      cached: false,
      errorKind,
      metadata: { cache_key: cacheKey, ...providerErrorMetadata(e) },
    });
    return fallback(errorKind);
  }

  if (!config.apiKey) {
    await releaseServiceUsageReservation(
      serviceClient,
      reservation.reservationId,
    )
      .catch(() => {});
    await recordUsage(serviceClient, {
      provider: config.provider,
      model: config.model,
      status: "fallback",
      cached: false,
      errorKind: "provider_unconfigured",
      metadata: { cache_key: cacheKey },
    });
    return fallback("provider_unconfigured");
  }

  const timeoutMs = numberFromConfig(reservation.config, "timeout_ms") ??
    DEFAULT_TIMEOUT_MS;
  const maxTokens = numberFromConfig(reservation.config, "max_tokens") ??
    DEFAULT_MAX_TOKENS;

  const started = Date.now();
  let modelOutput: { raw: unknown; inputUnits?: number; outputUnits?: number };
  try {
    modelOutput = await generateRouteDraft(config, input, {
      timeoutMs,
      maxTokens,
    });
  } catch (e) {
    const errorKind = classifyProviderError(e);
    await releaseServiceUsageReservation(
      serviceClient,
      reservation.reservationId,
    )
      .catch(() => {});
    await recordUsage(serviceClient, {
      provider: config.provider,
      model: config.model,
      status: isThrottle(errorKind) ? "throttled" : "error",
      cached: false,
      latencyMs: Date.now() - started,
      errorKind,
      metadata: { cache_key: cacheKey, ...providerErrorMetadata(e) },
    });
    return fallback(errorKind);
  }

  const validation = validateRouteDraft(modelOutput.raw, input);
  if (!validation.ok) {
    await releaseServiceUsageReservation(
      serviceClient,
      reservation.reservationId,
    )
      .catch(() => {});
    await recordUsage(serviceClient, {
      provider: config.provider,
      model: config.model,
      status: "invalid_output",
      cached: false,
      inputUnits: modelOutput.inputUnits,
      outputUnits: modelOutput.outputUnits,
      latencyMs: Date.now() - started,
      errorKind: validation.hardError ?? "invalid_output",
      metadata: { cache_key: cacheKey },
    });
    return fallback("invalid_output");
  }

  const draft = {
    draft_id: crypto.randomUUID(),
    ...validation.draft,
  };

  if (reservation.canCacheContent) {
    await writeCache(
      serviceClient,
      cacheKey,
      config,
      draft,
      reservation.cacheTtlSeconds ?? 0,
    ).catch(() => {});
  }
  await completeServiceUsageReservation(
    serviceClient,
    reservation.reservationId,
  )
    .catch(() => {});
  await recordUsage(serviceClient, {
    provider: config.provider,
    model: config.model,
    status: "success",
    cached: false,
    inputUnits: modelOutput.inputUnits,
    outputUnits: modelOutput.outputUnits,
    latencyMs: Date.now() - started,
    metadata: {
      cache_key: cacheKey,
      item_count: draft.plan_items.length,
      warning_count: draft.warnings.length,
    },
  });

  return json({ ok: true, status: "success", cached: false, draft });
});

function loadSupabaseEnv() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
  if (!url || !anonKey || !serviceKey) return null;
  return { url, anonKey, serviceKey };
}

async function verifyActiveMember(
  client: SupabaseClientLike,
  tripId: string,
  userId: string,
): Promise<boolean> {
  const { data, error } = await client
    .from("trip_members")
    .select("status")
    .eq("trip_id", tripId)
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle();
  return !error && !!data;
}

async function readCache(
  client: SupabaseClientLike,
  cacheKey: string,
): Promise<
  { provider: string | null; model: string | null; draft: JsonRecord } | null
> {
  const { data, error } = await client
    .from("trip_route_cache")
    .select("provider, model, draft, expires_at")
    .eq("cache_key", cacheKey)
    .maybeSingle();
  if (error || !data) return null;
  if (Date.parse(data.expires_at as string) <= Date.now()) return null;
  return {
    provider: data.provider as string | null,
    model: data.model as string | null,
    draft: data.draft as JsonRecord,
  };
}

async function writeCache(
  client: SupabaseClientLike,
  cacheKey: string,
  config: RouteAiProviderConfig,
  draft: JsonRecord,
  ttlSeconds: number,
): Promise<void> {
  if (ttlSeconds <= 0) return;
  await client.from("trip_route_cache").upsert({
    cache_key: cacheKey,
    provider: config.provider,
    model: config.model,
    draft,
    fetched_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + ttlSeconds * 1000).toISOString(),
  }, { onConflict: "cache_key" });
}

interface UsageEvent {
  provider: string;
  model?: string;
  status: "success" | "fallback" | "error" | "throttled" | "invalid_output";
  cached: boolean;
  inputUnits?: number;
  outputUnits?: number;
  latencyMs?: number;
  errorKind?: string;
  metadata?: JsonRecord;
}

async function recordUsage(client: SupabaseClientLike, event: UsageEvent) {
  try {
    await client.from("provider_usage_events").insert({
      feature: SERVICE,
      provider: event.provider,
      model: event.model ?? null,
      operation: "generate-route",
      status: event.status,
      cached: event.cached,
      input_units: event.inputUnits ?? null,
      output_units: event.outputUnits ?? null,
      estimated_cost_usd: null,
      latency_ms: event.latencyMs ?? null,
      error_kind: event.errorKind ?? null,
      metadata: event.metadata ?? {},
    });
  } catch (e) {
    console.error("provider_usage_events insert failed", e);
  }
}

function envelopeFingerprint(input: DraftInput): string {
  return JSON.stringify({
    d: input.destination.toLowerCase().trim(),
    s: input.tripStart,
    e: input.tripEnd,
    legs: input.legs.map((l) => [
      l.mode,
      l.windowStart,
      l.windowEnd,
      l.reachType,
      l.reachValueKm,
    ]),
  });
}

function classifyProviderError(error: unknown): string {
  if (error instanceof ProviderError) return error.kind;
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("429")) return "throttled";
  if (message.includes("timeout")) return "timeout";
  if (message.includes("provider_5")) return "provider_5xx";
  if (message.includes("provider_4")) return "provider_4xx";
  return "provider_error";
}

function isThrottle(kind: string): boolean {
  return kind === "throttled" || kind === "insufficient_quota";
}

function numberFromConfig(
  config: Record<string, unknown> | undefined,
  key: string,
): number | undefined {
  const v = config?.[key];
  return typeof v === "number" && Number.isFinite(v) ? v : undefined;
}

function fallback(reason: string) {
  return json({ ok: false, status: "fallback", reason, cached: false });
}

function json(body: JsonRecord, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
