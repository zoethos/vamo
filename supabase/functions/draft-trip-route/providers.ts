import { type DraftInput, ROUTE_JSON_SCHEMA } from "./draft.ts";

type JsonRecord = Record<string, unknown>;

const DEFAULT_OPENAI_BASE_URL = "https://api.openai.com/v1/";
const DEFAULT_OPENAI_MODEL = "gpt-4.1-mini";

export interface RouteAiProviderConfig {
  provider: string;
  adapter: "openai-chat-completions";
  model: string;
  apiKey: string;
  baseUrl: string;
  authHeader: "bearer" | "api-key";
}

export class ProviderError extends Error {
  constructor(kind: string, detail: JsonRecord = {}) {
    super(kind);
    this.kind = kind;
    this.detail = detail;
  }
  kind: string;
  detail: JsonRecord;
}

export function loadRouteAiProviderConfig(args: {
  provider: string | undefined;
  config: Record<string, unknown> | undefined;
}): RouteAiProviderConfig {
  const provider = (args.provider ?? "").trim().toLowerCase();
  const config = args.config ?? {};
  const adapter = stringFromConfig(config, "adapter") ??
    (provider === "openai" || provider === "azure-openai"
      ? "openai-chat-completions"
      : "");
  if (adapter !== "openai-chat-completions") {
    throw new ProviderError("unsupported_provider", { provider, adapter });
  }

  switch (provider) {
    case "openai": {
      return {
        provider,
        adapter,
        model: stringFromConfig(config, "model") ?? DEFAULT_OPENAI_MODEL,
        apiKey: Deno.env.get("VAMO_ROUTE_DRAFT_OPENAI_API_KEY")?.trim() ?? "",
        baseUrl: ensureTrailingSlash(
          stringFromConfig(config, "base_url") ?? DEFAULT_OPENAI_BASE_URL,
        ),
        authHeader: "bearer",
      };
    }
    case "azure-openai": {
      return {
        provider,
        adapter,
        model: stringFromConfig(config, "deployment") ??
          stringFromConfig(config, "model") ?? "",
        apiKey: Deno.env.get("VAMO_ROUTE_DRAFT_AZURE_OPENAI_API_KEY")?.trim() ??
          "",
        baseUrl: ensureTrailingSlash(
          stringFromConfig(config, "base_url") ?? "",
        ),
        authHeader: "api-key",
      };
    }
    default:
      throw new ProviderError("unsupported_provider", { provider });
  }
}

export async function generateRouteDraft(
  config: RouteAiProviderConfig,
  input: DraftInput,
  opts: { timeoutMs: number; maxTokens: number },
): Promise<{ raw: unknown; inputUnits?: number; outputUnits?: number }> {
  if (!config.model) throw new ProviderError("missing_model");
  if (!config.baseUrl) throw new ProviderError("missing_base_url");
  if (!config.apiKey) throw new ProviderError("provider_unconfigured");

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
              "Map legs to plan items: train->train, flight->flight, car/bike/bus/" +
              "motorbike->transfer (set transfer_subtype). Add visit/activity/" +
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

export function providerErrorMetadata(error: unknown): JsonRecord {
  return error instanceof ProviderError ? error.detail : {};
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
    return `  ${i}. ${leg.mode} - ${w} - ${reach}`;
  }).join("\n");
  return `Destination: ${input.destination}\nTrip window: ${window}\n` +
    `Legs (in order):\n${legs}\n` +
    `Reference each plan item to its leg via leg_index. Keep every item inside ` +
    `the trip window and its leg's window.`;
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

function numberOrUndefined(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
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

function ensureTrailingSlash(value: string): string {
  if (!value) return "";
  return value.endsWith("/") ? value : `${value}/`;
}
