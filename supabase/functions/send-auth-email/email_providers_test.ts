import {
  buildEmailProviderConfig,
  type EmailMessage,
  sendAuthEmailWithFallback,
} from "./email_providers.ts";

const message: EmailMessage = {
  to: "tester@example.com",
  subject: "Your Vamo code: 123456",
  html: "<p>123456</p>",
};

Deno.test("sendAuthEmailWithFallback uses Brevo first", async () => {
  const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
  const result = await sendAuthEmailWithFallback(
    message,
    config(),
    async (input, init) => {
      calls.push(capture(input, init));
      return new Response("{}", { status: 201 });
    },
  );

  assert(result.ok);
  assertEquals(result.provider, "brevo");
  assertEquals(calls.length, 1);
  assertEquals(calls[0].url, "https://api.brevo.com/v3/smtp/email");
  assertEquals(calls[0].body["htmlContent"], message.html);
});

Deno.test("sendAuthEmailWithFallback falls back to Resend after Brevo HTTP failure", async () => {
  const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
  const result = await sendAuthEmailWithFallback(
    message,
    config(),
    async (input, init) => {
      calls.push(capture(input, init));
      if (calls.length === 1) {
        return new Response("brevo down", { status: 503 });
      }
      return new Response('{"id":"resend-id"}', { status: 200 });
    },
  );

  assert(result.ok);
  assertEquals(result.provider, "resend");
  assertEquals(calls.length, 2);
  assertEquals(calls[1].url, "https://api.resend.com/emails");
  assertEquals(calls[1].body["from"], "Vamo <fallback@example.com>");
  assertEquals(calls[1].body["html"], message.html);
});

Deno.test("sendAuthEmailWithFallback falls back to Resend after Brevo network error", async () => {
  let calls = 0;
  const result = await sendAuthEmailWithFallback(
    message,
    config(),
    async () => {
      calls += 1;
      if (calls === 1) {
        throw new Error("network unavailable");
      }
      return new Response('{"id":"resend-id"}', { status: 200 });
    },
  );

  assert(result.ok);
  assertEquals(result.provider, "resend");
  assertEquals(calls, 2);
});

Deno.test("sendAuthEmailWithFallback reports failure when all providers fail", async () => {
  const result = await sendAuthEmailWithFallback(
    message,
    config(),
    async () => new Response("provider failed", { status: 500 }),
  );

  assert(!result.ok);
  assertEquals(result.attempts.length, 2);
  assertEquals(result.attempts.map((attempt) => attempt.provider), [
    "brevo",
    "resend",
  ]);
});

Deno.test("sendAuthEmailWithFallback skips unconfigured providers", async () => {
  let calls = 0;
  const result = await sendAuthEmailWithFallback(
    message,
    config({ brevoApiKey: "", resendApiKey: "" }),
    async () => {
      calls += 1;
      return new Response("should not be called", { status: 500 });
    },
  );

  assert(!result.ok);
  assertEquals(calls, 0);
  assertEquals(result.attempts, [
    { provider: "brevo", configured: false, ok: false },
    { provider: "resend", configured: false, ok: false },
  ]);
});

Deno.test("buildEmailProviderConfig defaults Resend sender to SENDER_EMAIL", () => {
  const result = buildEmailProviderConfig({
    BREVO_API_KEY: "brevo",
    RESEND_API_KEY: "resend",
    SENDER_EMAIL: "noreply@example.com",
  });

  assertEquals(result.resendSenderEmail, "noreply@example.com");
  assertEquals(result.senderName, "Vamo");
});

function config(
  overrides: Partial<ReturnType<typeof buildEmailProviderConfig>> = {},
): ReturnType<typeof buildEmailProviderConfig> {
  return {
    brevoApiKey: "brevo-key",
    resendApiKey: "resend-key",
    senderEmail: "primary@example.com",
    resendSenderEmail: "fallback@example.com",
    senderName: "Vamo",
    ...overrides,
  };
}

function capture(
  input: string | URL | Request,
  init?: RequestInit,
): { url: string; body: Record<string, unknown> } {
  return {
    url: typeof input === "string" ? input : input.toString(),
    body: JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>,
  };
}

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) {
    throw new Error(message);
  }
}

function assertEquals(actual: unknown, expected: unknown) {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`expected ${expectedJson}, got ${actualJson}`);
  }
}
