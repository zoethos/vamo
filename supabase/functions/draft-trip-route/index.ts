// Slice 2 — Advanced Travel Planning: draft a valid Plan from leg constraints.
// Deploy: supabase functions deploy draft-trip-route
//
// Secrets/config:
//   ROUTE_AI_PROVIDER=openai            (or azure-openai)
//   ROUTE_AI_MODEL=gpt-4.1-mini
//   ROUTE_AI_API_KEY=...
//   ROUTE_AI_BASE_URL=optional (Azure .../openai/v1/)
//   ROUTE_AI_DEPLOYMENT=optional Azure deployment/model override
//
// Requires Authorization: Bearer <user JWT>. Sends only the constraint envelope
// (destination, dates, modes, reach) — never trip names, members, or money.
// Proposes a draft only: NO Plan writes here (commit is Slice 3).

import { createClient } from "@supabase/supabase-js";
import {
  completeServiceUsageReservation,
  recordPremiumGateNotification,
  releaseServiceUsageReservation,
  reserveServiceUsage,
} from "../_shared/premium.ts";
import {
  type DraftInput,
  parseDraftInput,
  ROUTE_JSON_SCHEMA,
  validateRouteDraft,
} from "./draft.ts";

type JsonRecord = Record<string, unknown>;
type SupabaseClientLike = ReturnType<typeof createClient<any, "public", any>>;

const SERVICE = "draft-trip-route";
const DEFAULT_TIMEOUT_MS = 30_000;
const DEFAULT_MAX_TOKENS = 1400;

interface AiConfig {
  provider: string;
  model: string;
  apiKey: string;
  baseUrl: string;
  authHeader: "bearer" | "api-key";
}

class ProviderError extends Error {
  constructor(kind: string, detail: JsonRecord = {}) {
    super(kind);
    this.kind = kind;
    this.detail = detail;
  }
  kind: string;
  detail: JsonRecord;
}

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

  const config = loadAiConfig();
  const cacheKey = await sha256Hex(envelopeFingerprint(input));

  // Cache first — a reusable draft for an identical envelope is free.
  const cached = await readCache(serviceClient, cacheKey);
  if (cached) {
    await recordUsage(serviceClient, {
      provider: config.provider,
      model: cached.model,
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
      provider: config.provider,
      model: config.model,
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
    modelOutput = await generateRoute(config, input, { timeoutMs, maxTokens });
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

async function generateRoute(
  config: AiConfig,
  input: DraftInput,
  opts: { timeoutMs: number; maxTokens: number },
): Promise<{ raw: unknown; inputUnits?: number; outputUnits?: number }> {
  if (!config.baseUrl) throw new ProviderError("missing_base_url");
  const endpoint = new URL("chat/completions", config.baseUrl).toString();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (config.authHeader === "api-key") {
    headers["api-key"] = config.apiKey;
  } else {
    headers.Authorization = `Bearer ${config.apiKey}`;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs);
  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers,
      signal: controller.signal,
      body: JSON.stringify({
        model: config.model,
        temperature: 0.4,
        max_tokens: opts.maxTokens,
        messages: [
          {
            role: "system",
            content:
              "You plan a valid travel itinerary INSIDE the user's constraints. " +
              "Each leg gives a transport mode, an optional date window, and a " +
              "reach cap (max km, or max hours/day). Sequence stops so each hop " +
              "respects the leg covering those dates and never exceeds its reach. " +
              "Map legs to plan items: train→train, flight→flight, car/bike/bus/" +
              "motorbike→transfer (set transfer_subtype). Add visit/activity/" +
              "lodging stops as helpful. Use only the destination and dates given. " +
              "Never include people, emails, money, or private data. If something " +
              "can't be resolved, add an unresolved_question instead of guessing. " +
              "Return JSON only.",
          },
          { role: "user", content: promptForInput(input) },
        ],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "vamo_route_draft",
            strict: true,
            schema: ROUTE_JSON_SCHEMA,
          },
        },
      }),
    });
    if (!response.ok) throw await providerHttpError(response);
    const payload = await response.json() as JsonRecord;
    const choices = Array.isArray(payload.choices) ? payload.choices : [];
    const message = (choices[0] as JsonRecord | undefined)?.message as
      | JsonRecord
      | undefined;
    const content = typeof message?.content === "string" ? message.content : "";
    if (!content) throw new Error("empty_provider_content");
    const usage = payload.usage as JsonRecord | undefined;
    return {
      raw: JSON.parse(content),
      inputUnits: numberOrUndefined(usage?.prompt_tokens),
      outputUnits: numberOrUndefined(usage?.completion_tokens),
    };
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new ProviderError("timeout");
    }
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

function promptForInput(input: DraftInput): string {
  const window = input.tripStart && input.tripEnd
    ? `${input.tripStart} to ${input.tripEnd}`
    : "dates open";
  const legs = input.legs.map((leg, i) => {
    const w = leg.windowStart && leg.windowEnd
      ? `${leg.windowStart}..${leg.windowEnd}`
      : "any dates";
    const reach = leg.reachValueKm === null
      ? "no reach cap"
      : leg.reachType === "distance"
      ? `<= ${leg.reachValueKm} km`
      : `<= ${leg.reachValueKm} h/day`;
    return `  ${i}. ${leg.mode} · ${w} · ${reach}`;
  }).join("\n");
  return `Destination: ${input.destination}\nTrip window: ${window}\n` +
    `Legs (in order):\n${legs}\n` +
    `Reference each plan item to its leg via leg_index. Keep every item inside ` +
    `the trip window and its leg's window.`;
}

function loadSupabaseEnv() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
  if (!url || !anonKey || !serviceKey) return null;
  return { url, anonKey, serviceKey };
}

function loadAiConfig(): AiConfig {
  const provider = (Deno.env.get("ROUTE_AI_PROVIDER") ?? "openai")
    .trim().toLowerCase();
  const deployment = Deno.env.get("ROUTE_AI_DEPLOYMENT")?.trim();
  const model = deployment || Deno.env.get("ROUTE_AI_MODEL")?.trim() ||
    "gpt-4.1-mini";
  const apiKey = Deno.env.get("ROUTE_AI_API_KEY")?.trim() ||
    Deno.env.get("OPENAI_API_KEY")?.trim() || "";
  const baseUrl = ensureTrailingSlash(
    Deno.env.get("ROUTE_AI_BASE_URL")?.trim() ||
      (provider === "azure-openai" ? "" : "https://api.openai.com/v1/"),
  );
  return {
    provider,
    model,
    apiKey,
    baseUrl,
    authHeader: provider === "azure-openai" ? "api-key" : "bearer",
  };
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
): Promise<{ model: string | null; draft: JsonRecord } | null> {
  const { data, error } = await client
    .from("trip_route_cache")
    .select("model, draft, expires_at")
    .eq("cache_key", cacheKey)
    .maybeSingle();
  if (error || !data) return null;
  if (Date.parse(data.expires_at as string) <= Date.now()) return null;
  return {
    model: data.model as string | null,
    draft: data.draft as JsonRecord,
  };
}

async function writeCache(
  client: SupabaseClientLike,
  cacheKey: string,
  config: AiConfig,
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

async function providerHttpError(response: Response): Promise<ProviderError> {
  const detail: JsonRecord = { provider_status: response.status };
  try {
    const body = await response.json() as JsonRecord;
    const error = body.error as JsonRecord | undefined;
    if (typeof error?.type === "string") {
      detail.provider_error_type = error.type;
    }
    if (typeof error?.code === "string") {
      detail.provider_error_code = error.code;
    }
  } catch {
    // status alone is enough to classify.
  }
  if (response.status === 429) return new ProviderError("throttled", detail);
  if (response.status >= 500) return new ProviderError("provider_5xx", detail);
  return new ProviderError("provider_4xx", detail);
}

function providerErrorMetadata(error: unknown): JsonRecord {
  return error instanceof ProviderError ? error.detail : {};
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

function numberOrUndefined(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

function ensureTrailingSlash(value: string): string {
  if (!value) return "";
  return value.endsWith("/") ? value : `${value}/`;
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
