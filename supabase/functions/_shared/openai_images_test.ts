import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import {
  destinationImagePrompt,
  generateDestinationImage,
} from "./openai_images.ts";

Deno.test("destinationImagePrompt forbids people text and logos", () => {
  const prompt = destinationImagePrompt("Amalfi Coast");
  assert(prompt.includes("Amalfi Coast"));
  assert(prompt.includes("No people"));
  assert(prompt.includes("no text"));
  assert(prompt.includes("no logos"));
});

Deno.test("generateDestinationImage parses base64 response", async () => {
  const calls: RequestInit[] = [];
  const fetcher = (async (_input: URL | RequestInfo, init?: RequestInit) => {
    calls.push(init ?? {});
    return new Response(
      JSON.stringify({ data: [{ b64_json: "AQID" }] }),
      { status: 200 },
    );
  }) as typeof fetch;

  const image = await generateDestinationImage({
    apiKey: "key",
    destination: "Amalfi Coast",
    fetcher,
  });

  assertEquals(image?.source, "ai");
  assertEquals(image?.imageBase64, "AQID");
  assertEquals(image?.mimeType, "image/png");
  assertEquals(calls.length, 1);
});
