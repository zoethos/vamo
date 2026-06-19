export type EmailProviderName = "brevo" | "resend";

export interface EmailMessage {
  to: string;
  subject: string;
  html: string;
}

export interface EmailProviderConfig {
  brevoApiKey: string;
  resendApiKey: string;
  senderEmail: string;
  resendSenderEmail: string;
  senderName: string;
}

export interface EmailSendAttempt {
  provider: EmailProviderName;
  configured: boolean;
  ok: boolean;
  status?: number;
  detail?: string;
}

export interface EmailSendResult {
  ok: boolean;
  provider?: EmailProviderName;
  attempts: EmailSendAttempt[];
}

type FetchLike = typeof fetch;

const BREVO_ENDPOINT = "https://api.brevo.com/v3/smtp/email";
const RESEND_ENDPOINT = "https://api.resend.com/emails";

export function buildEmailProviderConfig(
  env: Record<string, string | undefined> = Deno.env.toObject(),
): EmailProviderConfig {
  const senderEmail = readEnv(env, "SENDER_EMAIL");
  return {
    brevoApiKey: readEnv(env, "BREVO_API_KEY"),
    resendApiKey: readEnv(env, "RESEND_API_KEY"),
    senderEmail,
    resendSenderEmail: readEnv(env, "RESEND_SENDER_EMAIL") || senderEmail,
    senderName: readEnv(env, "SENDER_NAME") || "Vamo",
  };
}

export async function sendAuthEmailWithFallback(
  message: EmailMessage,
  config: EmailProviderConfig,
  fetcher: FetchLike = fetch,
): Promise<EmailSendResult> {
  const attempts: EmailSendAttempt[] = [];
  const brevo = await sendViaBrevo(message, config, fetcher);
  attempts.push(brevo);
  if (brevo.ok) {
    return { ok: true, provider: "brevo", attempts };
  }

  const resend = await sendViaResend(message, config, fetcher);
  attempts.push(resend);
  if (resend.ok) {
    return { ok: true, provider: "resend", attempts };
  }

  return { ok: false, attempts };
}

async function sendViaBrevo(
  message: EmailMessage,
  config: EmailProviderConfig,
  fetcher: FetchLike,
): Promise<EmailSendAttempt> {
  if (!config.brevoApiKey || !config.senderEmail) {
    return { provider: "brevo", configured: false, ok: false };
  }

  return sendProviderRequest("brevo", () =>
    fetcher(BREVO_ENDPOINT, {
      method: "POST",
      headers: {
        "api-key": config.brevoApiKey,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        sender: { name: config.senderName, email: config.senderEmail },
        to: [{ email: message.to }],
        subject: message.subject,
        htmlContent: message.html,
      }),
    }));
}

async function sendViaResend(
  message: EmailMessage,
  config: EmailProviderConfig,
  fetcher: FetchLike,
): Promise<EmailSendAttempt> {
  if (!config.resendApiKey || !config.resendSenderEmail) {
    return { provider: "resend", configured: false, ok: false };
  }

  return sendProviderRequest("resend", () =>
    fetcher(RESEND_ENDPOINT, {
      method: "POST",
      headers: {
        "authorization": `Bearer ${config.resendApiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        from: `${config.senderName} <${config.resendSenderEmail}>`,
        to: [message.to],
        subject: message.subject,
        html: message.html,
      }),
    }));
}

async function sendProviderRequest(
  provider: EmailProviderName,
  request: () => Promise<Response>,
): Promise<EmailSendAttempt> {
  try {
    const response = await request();
    if (response.ok) {
      return {
        provider,
        configured: true,
        ok: true,
        status: response.status,
      };
    }
    return {
      provider,
      configured: true,
      ok: false,
      status: response.status,
      detail: trimDetail(await response.text()),
    };
  } catch (err) {
    return {
      provider,
      configured: true,
      ok: false,
      detail: trimDetail(err instanceof Error ? err.message : String(err)),
    };
  }
}

function readEnv(
  env: Record<string, string | undefined>,
  name: string,
): string {
  return (env[name] ?? "").trim();
}

function trimDetail(detail: string): string {
  return detail.length <= 500 ? detail : `${detail.substring(0, 500)}...`;
}
