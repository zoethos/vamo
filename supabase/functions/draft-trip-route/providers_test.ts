import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { loadRouteAiProviderConfig, ProviderError } from "./providers.ts";

Deno.test("loadRouteAiProviderConfig binds OpenAI routing to provider_config + provider-specific secret", () => {
  const previous = Deno.env.get("VAMO_ROUTE_DRAFT_OPENAI_API_KEY");
  Deno.env.set("VAMO_ROUTE_DRAFT_OPENAI_API_KEY", "test-key");
  try {
    const config = loadRouteAiProviderConfig({
      provider: "openai",
      config: {
        adapter: "openai-chat-completions",
        model: "gpt-4.1-mini",
        base_url: "https://api.openai.com/v1/",
      },
    });

    assertEquals(config.provider, "openai");
    assertEquals(config.model, "gpt-4.1-mini");
    assertEquals(config.baseUrl, "https://api.openai.com/v1/");
    assertEquals(config.apiKey, "test-key");
    assertEquals(config.authHeader, "bearer");
  } finally {
    if (previous === undefined) {
      Deno.env.delete("VAMO_ROUTE_DRAFT_OPENAI_API_KEY");
    } else {
      Deno.env.set("VAMO_ROUTE_DRAFT_OPENAI_API_KEY", previous);
    }
  }
});

Deno.test("loadRouteAiProviderConfig fails closed for unsupported providers", () => {
  assertThrows(
    () =>
      loadRouteAiProviderConfig({
        provider: "example-ai",
        config: { adapter: "example-adapter" },
      }),
    ProviderError,
    "unsupported_provider",
  );
});
