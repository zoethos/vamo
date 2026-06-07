// S23 — Resolve a trip share/snapshot theme from destination only.
// Deploy: supabase functions deploy resolve-theme
//
// Secrets/config:
//   THEME_AI_PROVIDER=openai
//   THEME_AI_MODEL=gpt-4.1-nano
//   THEME_AI_API_KEY=...
//   THEME_AI_BASE_URL=optional, e.g. Azure .../openai/v1/
//   THEME_AI_DEPLOYMENT=optional Azure deployment/model override
//
// Requires Authorization: Bearer <user JWT>. Never send trip names, member data,
// balances, invite tokens, or emails to the model provider.

import { createClient } from "@supabase/supabase-js";

type JsonRecord = Record<string, unknown>;
type SupabaseClientLike = ReturnType<typeof createClient<any, "public", any>>;

interface ResolveThemeRequest {
  trip_id?: unknown;
  destination?: unknown;
}

interface ThemePack {
  id: string;
  label: string;
  gradient: string[];
  statBackground: string;
  statPrimary: string;
  statMuted: string;
  accent: string;
  memberBubble: string;
  memberInitial: string;
  tagline: string;
}

interface ThemeAiConfig {
  provider: string;
  model: string;
  apiKey: string;
  baseUrl: string;
  authHeader: "bearer" | "api-key";
}

interface GeneratedTheme {
  canonicalKey: string;
  displayName: string;
  pack: ThemePack;
  inputUnits?: number;
  outputUnits?: number;
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

class ProviderError extends Error {
  constructor(kind: string, detail: JsonRecord = {}) {
    super(kind);
    this.kind = kind;
    this.detail = detail;
  }

  kind: string;
  detail: JsonRecord;
}

const THEME_SCHEMA_VERSION = 1;
const AI_TIMEOUT_MS = 4_000;
const MAX_DESTINATION_CHARS = 80;
const HEX_RE = /^#[0-9A-Fa-f]{6}$/;
const CANONICAL_KEY_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;
const THEME_KEYS = [
  "id",
  "label",
  "gradient",
  "statBackground",
  "statPrimary",
  "statMuted",
  "accent",
  "memberBubble",
  "memberInitial",
  "tagline",
] as const;

const DEFAULT_PACK: ThemePack = {
  id: "default",
  label: "Vamo",
  gradient: ["#FF5B4D", "#6A2D6F"],
  statBackground: "#FFE6EC",
  statPrimary: "#0C0E16",
  statMuted: "#2A2E3A",
  accent: "#FF5B4D",
  memberBubble: "#FFE6EC",
  memberInitial: "#0C0E16",
  tagline: "Si va?",
};

const THEME_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["canonicalKey", "displayName", "pack"],
  properties: {
    canonicalKey: {
      type: "string",
      description: "Stable lowercase destination key, e.g. rome-it.",
      minLength: 1,
      maxLength: 64,
    },
    displayName: {
      type: "string",
      description: "Human-readable destination name.",
      minLength: 1,
      maxLength: 40,
    },
    pack: {
      type: "object",
      additionalProperties: false,
      required: THEME_KEYS,
      properties: {
        id: { type: "string", minLength: 1, maxLength: 64 },
        label: { type: "string", minLength: 1, maxLength: 40 },
        gradient: {
          type: "array",
          minItems: 3,
          maxItems: 3,
          items: { type: "string", minLength: 7, maxLength: 7 },
        },
        statBackground: { type: "string", minLength: 7, maxLength: 7 },
        statPrimary: { type: "string", minLength: 7, maxLength: 7 },
        statMuted: { type: "string", minLength: 7, maxLength: 7 },
        accent: { type: "string", minLength: 7, maxLength: 7 },
        memberBubble: { type: "string", minLength: 7, maxLength: 7 },
        memberInitial: { type: "string", minLength: 7, maxLength: 7 },
        tagline: { type: "string", minLength: 1, maxLength: 16 },
      },
    },
  },
};

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
  if (!env) {
    return json({ ok: false, error: "missing_supabase_env" }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }
  const jwt = authHeader.slice("Bearer ".length);

  const userClient = createClient(env.url, env.anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const serviceClient = createClient(env.url, env.serviceKey);

  const { data: userData, error: userError } = await userClient.auth.getUser(jwt);
  if (userError || !userData.user) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  let payload: ResolveThemeRequest;
  try {
    payload = await req.json() as ResolveThemeRequest;
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  const tripId = typeof payload.trip_id === "string" ? payload.trip_id : "";
  if (!isUuid(tripId)) {
    return json({ ok: false, error: "invalid_trip_id" }, 400);
  }

  const canSetTheme = await verifyTripThemeWriter(
    serviceClient,
    tripId,
    userData.user.id,
  );
  if (!canSetTheme) {
    return json({ ok: false, error: "forbidden" }, 403);
  }

  const rawDestination =
    typeof payload.destination === "string" ? payload.destination : "";
  const normalized = normalizeDestination(rawDestination);
  const destinationHash = await sha256Hex(normalized);
  const config = loadThemeAiConfig();

  if (!isCacheableDestination(normalized, rawDestination)) {
    await recordUsage(serviceClient, {
      provider: config.provider,
      model: config.model,
      status: "fallback",
      cached: false,
      errorKind: "invalid_destination",
      metadata: { destination_hash: destinationHash },
    });
    return fallback("invalid_destination");
  }

  const cached = await resolveFromCache(serviceClient, normalized);
  if (cached) {
    const applied = await tryApplyTheme(serviceClient, tripId, cached.pack);
    if (!applied) {
      await recordUsage(serviceClient, {
        provider: config.provider,
        model: cached.model,
        status: "error",
        cached: true,
        errorKind: "apply_theme_failed",
        metadata: {
          canonical_key: cached.canonicalKey,
          destination_hash: destinationHash,
        },
      });
      return fallback("apply_theme_failed");
    }
    await recordUsage(serviceClient, {
      provider: config.provider,
      model: cached.model,
      status: "success",
      cached: true,
      metadata: {
        canonical_key: cached.canonicalKey,
        destination_hash: destinationHash,
      },
    });
    return json({
      ok: true,
      status: "success",
      cached: true,
      canonical_key: cached.canonicalKey,
      theme: cached.pack,
    });
  }

  if (!config.apiKey) {
    await recordUsage(serviceClient, {
      provider: config.provider,
      model: config.model,
      status: "fallback",
      cached: false,
      errorKind: "missing_api_key",
      metadata: { destination_hash: destinationHash },
    });
    return fallback("missing_api_key");
  }

  const started = Date.now();
  let generated: GeneratedTheme;
  try {
    generated = await generateTheme(config, normalized);
  } catch (e) {
    const errorKind = classifyProviderError(e);
    await recordUsage(serviceClient, {
      provider: config.provider,
      model: config.model,
      status: isProviderThrottle(errorKind) ? "throttled" : "fallback",
      cached: false,
      latencyMs: Date.now() - started,
      errorKind,
      metadata: {
        destination_hash: destinationHash,
        ...providerErrorMetadata(e),
      },
    });
    return fallback(errorKind);
  }

  const validationError = validateGeneratedTheme(generated);
  if (validationError) {
    await recordUsage(serviceClient, {
      provider: config.provider,
      model: config.model,
      status: "invalid_output",
      cached: false,
      inputUnits: generated.inputUnits,
      outputUnits: generated.outputUnits,
      latencyMs: Date.now() - started,
      errorKind: validationError,
      metadata: { destination_hash: destinationHash },
    });
    return fallback("invalid_output");
  }

  const existing = await loadThemeByCanonical(
    serviceClient,
    generated.canonicalKey,
  );
  const pack = existing?.pack ?? generated.pack;
  const model = existing?.model ?? config.model;

  if (!existing) {
    const { error: themeError } = await serviceClient
      .from("destination_themes")
      .upsert({
        canonical_key: generated.canonicalKey,
        pack,
        display_name: generated.displayName,
        model,
        schema_version: THEME_SCHEMA_VERSION,
        review_status: "auto",
        updated_at: new Date().toISOString(),
      }, { onConflict: "canonical_key" });
    if (themeError) {
      await recordUsage(serviceClient, {
        provider: config.provider,
        model: config.model,
        status: "error",
        cached: false,
        inputUnits: generated.inputUnits,
        outputUnits: generated.outputUnits,
        latencyMs: Date.now() - started,
        errorKind: "theme_upsert_failed",
        metadata: { destination_hash: destinationHash },
      });
      return fallback("theme_upsert_failed");
    }
  }

  await serviceClient
    .from("destination_theme_aliases")
    .upsert({
      alias: normalized,
      canonical_key: generated.canonicalKey,
    }, { onConflict: "alias" });

  const applied = await tryApplyTheme(serviceClient, tripId, pack);
  if (!applied) {
    await recordUsage(serviceClient, {
      provider: config.provider,
      model,
      status: "error",
      cached: false,
      inputUnits: generated.inputUnits,
      outputUnits: generated.outputUnits,
      latencyMs: Date.now() - started,
      errorKind: "apply_theme_failed",
      metadata: {
        canonical_key: generated.canonicalKey,
        destination_hash: destinationHash,
      },
    });
    return fallback("apply_theme_failed");
  }
  await recordUsage(serviceClient, {
    provider: config.provider,
    model,
    status: "success",
    cached: false,
    inputUnits: generated.inputUnits,
    outputUnits: generated.outputUnits,
    latencyMs: Date.now() - started,
    metadata: {
      canonical_key: generated.canonicalKey,
      destination_hash: destinationHash,
    },
  });

  return json({
    ok: true,
    status: "success",
    cached: false,
    canonical_key: generated.canonicalKey,
    theme: pack,
  });
});

function loadSupabaseEnv() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    readNamedKey("SUPABASE_PUBLISHABLE_KEYS", "default");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SECRET_KEY") ??
    readNamedKey("SUPABASE_SECRET_KEYS", "default");
  if (!url || !anonKey || !serviceKey) return null;
  return { url, anonKey, serviceKey };
}

function readNamedKey(envName: string, keyName: string): string {
  const raw = Deno.env.get(envName);
  if (!raw) return "";
  try {
    const parsed = JSON.parse(raw) as Record<string, string>;
    return parsed[keyName] ?? "";
  } catch {
    return "";
  }
}

function loadThemeAiConfig(): ThemeAiConfig {
  const provider = (Deno.env.get("THEME_AI_PROVIDER") ?? "openai")
    .trim()
    .toLowerCase();
  const deployment = Deno.env.get("THEME_AI_DEPLOYMENT")?.trim();
  const model = deployment || Deno.env.get("THEME_AI_MODEL")?.trim() ||
    "gpt-4.1-nano";
  const apiKey = Deno.env.get("THEME_AI_API_KEY")?.trim() ||
    Deno.env.get("OPENAI_API_KEY")?.trim() ||
    "";
  const baseUrl = ensureTrailingSlash(
    Deno.env.get("THEME_AI_BASE_URL")?.trim() ||
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

async function verifyTripThemeWriter(
  client: SupabaseClientLike,
  tripId: string,
  userId: string,
): Promise<boolean> {
  const { data, error } = await client
    .from("trip_members")
    .select("role, status")
    .eq("trip_id", tripId)
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle();
  if (error || !data) return false;
  return data.role === "owner" || data.role === "co-admin";
}

async function resolveFromCache(
  client: SupabaseClientLike,
  alias: string,
): Promise<{ canonicalKey: string; model: string; pack: ThemePack } | null> {
  const { data: aliasRow, error: aliasError } = await client
    .from("destination_theme_aliases")
    .select("canonical_key")
    .eq("alias", alias)
    .maybeSingle();
  if (aliasError || !aliasRow?.canonical_key) return null;
  return loadThemeByCanonical(client, aliasRow.canonical_key as string);
}

async function loadThemeByCanonical(
  client: SupabaseClientLike,
  canonicalKey: string,
): Promise<{ canonicalKey: string; model: string; pack: ThemePack } | null> {
  const { data, error } = await client
    .from("destination_themes")
    .select("canonical_key, model, pack")
    .eq("canonical_key", canonicalKey)
    .eq("schema_version", THEME_SCHEMA_VERSION)
    .maybeSingle();
  if (error || !data) return null;
  const pack = coerceThemePack(data.pack);
  if (!pack || pack.id !== canonicalKey) return null;
  return pack
    ? {
      canonicalKey,
      model: data.model as string,
      pack,
    }
    : null;
}

async function applyTheme(
  client: SupabaseClientLike,
  tripId: string,
  pack: ThemePack,
) {
  const { error } = await client.rpc("_apply_trip_theme", {
    p_trip_id: tripId,
    p_theme: pack,
  });
  if (error) throw new Error("apply_theme_failed");
}

async function tryApplyTheme(
  client: SupabaseClientLike,
  tripId: string,
  pack: ThemePack,
): Promise<boolean> {
  try {
    await applyTheme(client, tripId, pack);
    return true;
  } catch {
    return false;
  }
}

async function generateTheme(
  config: ThemeAiConfig,
  normalizedDestination: string,
): Promise<GeneratedTheme> {
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
  const timeout = setTimeout(() => controller.abort(), AI_TIMEOUT_MS);
  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers,
      signal: controller.signal,
      body: JSON.stringify({
        model: config.model,
        temperature: 0.7,
        max_tokens: 500,
        messages: [
          {
            role: "system",
            content:
              "You design compact destination color themes for Vamo trip cards. " +
              "Use only the provided destination. Never infer or include people, " +
              "emails, money, trip names, or private details. Return JSON only.",
          },
          {
            role: "user",
            content:
              `Destination: ${normalizedDestination}\n` +
              "Create a dark, evocative three-color gradient and high-contrast " +
              "card tokens. The tagline should be a local-language 'let's go' " +
              "phrase, max 16 chars, no digits, no URL.",
          },
        ],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "vamo_snapshot_theme",
            strict: true,
            schema: THEME_JSON_SCHEMA,
          },
        },
      }),
    });
    if (!response.ok) {
      throw await providerHttpError(response);
    }

    const body = await response.json() as JsonRecord;
    const choices = Array.isArray(body.choices) ? body.choices : [];
    const message = (choices[0] as JsonRecord | undefined)?.message as
      | JsonRecord
      | undefined;
    const content = typeof message?.content === "string" ? message.content : "";
    if (!content) throw new Error("empty_provider_content");

    const parsed = JSON.parse(content) as JsonRecord;
    const usage = body.usage as JsonRecord | undefined;
    return {
      canonicalKey: String(parsed.canonicalKey ?? ""),
      displayName: String(parsed.displayName ?? ""),
      pack: parsed.pack as ThemePack,
      inputUnits: numberOrUndefined(usage?.prompt_tokens),
      outputUnits: numberOrUndefined(usage?.completion_tokens),
    };
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new ProviderError("timeout");
    }
    throw e;
  } finally {
    clearTimeout(timeout);
  }
}

function validateGeneratedTheme(theme: GeneratedTheme): string | null {
  if (!CANONICAL_KEY_RE.test(theme.canonicalKey)) return "bad_canonical_key";
  if (theme.displayName.trim().length < 1 || theme.displayName.length > 40) {
    return "bad_display_name";
  }
  if (theme.pack?.id !== theme.canonicalKey) return "id_mismatch";
  return validateThemePack(theme.pack);
}

function coerceThemePack(raw: unknown): ThemePack | null {
  if (!raw || typeof raw !== "object") return null;
  const pack = raw as ThemePack;
  return validateThemePack(pack) ? null : pack;
}

function validateThemePack(pack: ThemePack): string | null {
  if (!pack || typeof pack !== "object") return "not_object";
  const keys = Object.keys(pack);
  if (
    keys.length !== THEME_KEYS.length ||
    THEME_KEYS.some((key) => !Object.hasOwn(pack, key))
  ) {
    return "bad_keys";
  }
  if (!CANONICAL_KEY_RE.test(pack.id)) return "bad_id";
  if (typeof pack.label !== "string" || pack.label.length > 40) {
    return "bad_label";
  }
  if (
    !Array.isArray(pack.gradient) ||
    pack.gradient.length < 2 ||
    pack.gradient.length > 3 ||
    pack.gradient.some((color) => !isHex(color))
  ) {
    return "bad_gradient";
  }
  for (
    const key of [
      "statBackground",
      "statPrimary",
      "statMuted",
      "accent",
      "memberBubble",
      "memberInitial",
    ] as const
  ) {
    if (!isHex(pack[key])) return `bad_${key}`;
  }
  if (pack.gradient.some((color) => contrastRatio("#FFFFFF", color) < 4.5)) {
    return "low_gradient_contrast";
  }
  if (contrastRatio(pack.statPrimary, pack.statBackground) < 4.5) {
    return "low_stat_contrast";
  }
  if (contrastRatio(pack.memberInitial, pack.memberBubble) < 4.5) {
    return "low_member_contrast";
  }
  if (
    typeof pack.tagline !== "string" ||
    pack.tagline.length < 1 ||
    pack.tagline.length > 16 ||
    /[\r\n0-9]/.test(pack.tagline) ||
    /(https?:\/\/|www\.)/i.test(pack.tagline)
  ) {
    return "bad_tagline";
  }
  return null;
}

async function recordUsage(
  client: SupabaseClientLike,
  event: UsageEvent,
) {
  try {
    await client.from("provider_usage_events").insert({
      feature: "theme",
      provider: event.provider,
      model: event.model ?? null,
      operation: "resolve-theme",
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

function normalizeDestination(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[’']/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function isCacheableDestination(normalized: string, raw: string): boolean {
  return normalized.length >= 2 &&
    normalized.length <= MAX_DESTINATION_CHARS &&
    !/(https?:|www\.|@)/i.test(raw);
}

function classifyProviderError(error: unknown): string {
  if (error instanceof ProviderError) return error.kind;
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("provider_throttled") || message.includes("429")) {
    return "throttled";
  }
  if (message.includes("timeout")) return "timeout";
  if (message.includes("missing_base_url")) return "missing_base_url";
  if (message.includes("provider_5")) return "provider_5xx";
  if (message.includes("provider_4")) return "provider_4xx";
  return "provider_error";
}

async function providerHttpError(response: Response): Promise<ProviderError> {
  const detail: JsonRecord = { provider_status: response.status };
  try {
    const body = await response.json() as JsonRecord;
    const error = body.error as JsonRecord | undefined;
    const type = stringOrUndefined(error?.type);
    const code = stringOrUndefined(error?.code);
    const param = stringOrUndefined(error?.param);
    if (type) detail.provider_error_type = type;
    if (code) detail.provider_error_code = code;
    if (param) detail.provider_error_param = param;
  } catch {
    // Body shape is provider-specific; status alone is enough to classify.
  }

  const providerType = String(detail.provider_error_type ?? "");
  const providerCode = String(detail.provider_error_code ?? "");
  if (response.status === 429) {
    const quotaSignals = new Set([
      "insufficient_quota",
      "billing_hard_limit_reached",
      "billing_not_active",
    ]);
    const kind = quotaSignals.has(providerType) || quotaSignals.has(providerCode)
      ? "insufficient_quota"
      : "throttled";
    return new ProviderError(kind, detail);
  }
  if (response.status >= 500) return new ProviderError("provider_5xx", detail);
  return new ProviderError("provider_4xx", detail);
}

function providerErrorMetadata(error: unknown): JsonRecord {
  return error instanceof ProviderError ? error.detail : {};
}

function isProviderThrottle(errorKind: string): boolean {
  return errorKind === "throttled" || errorKind === "insufficient_quota";
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function isHex(value: string): boolean {
  return typeof value === "string" && HEX_RE.test(value);
}

function ensureTrailingSlash(value: string): string {
  if (!value) return "";
  return value.endsWith("/") ? value : `${value}/`;
}

function numberOrUndefined(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function stringOrUndefined(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function fallback(reason: string) {
  return json({
    ok: false,
    status: "fallback",
    reason,
    cached: false,
    theme: DEFAULT_PACK,
  });
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
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function contrastRatio(a: string, b: string): number {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  const lighter = Math.max(la, lb);
  const darker = Math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

function relativeLuminance(hex: string): number {
  const rgb = hexToRgb(hex);
  const [r, g, b] = [rgb.r, rgb.g, rgb.b].map((channel) => {
    const value = channel / 255;
    return value <= 0.03928
      ? value / 12.92
      : Math.pow((value + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function hexToRgb(hex: string): { r: number; g: number; b: number } {
  const normalized = hex.slice(1);
  return {
    r: parseInt(normalized.slice(0, 2), 16),
    g: parseInt(normalized.slice(2, 4), 16),
    b: parseInt(normalized.slice(4, 6), 16),
  };
}
