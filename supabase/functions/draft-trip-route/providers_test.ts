import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { loadRouteAiProviderConfig, ProviderError } from "./providers.ts";

Deno.test("loadRouteAiProviderConfig binds OpenAI routing to provider_config + environment-scoped secret", () => {
  const previousShared = Deno.env.get("VAMO_OPENAI_API_KEY");
  const previousProd = Deno.env.get("VAMO_OPENAI_PROD_API_KEY");
  const previousStaging = Deno.env.get("VAMO_OPENAI_STAGING_API_KEY");
  Deno.env.delete("VAMO_OPENAI_API_KEY");
  Deno.env.delete("VAMO_OPENAI_PROD_API_KEY");
  Deno.env.set("VAMO_OPENAI_STAGING_API_KEY", "test-key");
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
    restoreEnv("VAMO_OPENAI_API_KEY", previousShared);
    restoreEnv("VAMO_OPENAI_PROD_API_KEY", previousProd);
    restoreEnv("VAMO_OPENAI_STAGING_API_KEY", previousStaging);
  }
});

function restoreEnv(name: string, value: string | undefined) {
  if (value === undefined) {
    Deno.env.delete(name);
  } else {
    Deno.env.set(name, value);
  }
}

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
