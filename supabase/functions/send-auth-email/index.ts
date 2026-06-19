// Send Email Auth Hook — replaces Supabase's built-in auth emails.
// Receives the signed hook payload, sends the email via Brevo's HTTP API,
// then falls back to Resend if Brevo fails.
//
// Required secrets (supabase secrets set KEY=value):
//   SEND_EMAIL_HOOK_SECRET  - from the dashboard when registering the hook (v1,whsec_...)
//   BREVO_API_KEY           - Brevo > SMTP & API > API keys
//   SENDER_EMAIL            - your Brevo-verified sender address
//   RESEND_API_KEY          - fallback provider key
// Optional:
//   RESEND_SENDER_EMAIL     - fallback sender, defaults to SENDER_EMAIL
//   SENDER_NAME             - friendly sender name, defaults to Vamo
//
// Deploy: supabase functions deploy send-auth-email --no-verify-jwt

import { Webhook } from "standardwebhooks";
import {
  buildEmailProviderConfig,
  sendAuthEmailWithFallback,
} from "./email_providers.ts";

const HOOK_SECRET = (Deno.env.get("SEND_EMAIL_HOOK_SECRET") ?? "").replace(
  "v1,whsec_",
  "",
);

interface EmailData {
  token: string;
  token_hash: string;
  redirect_to: string;
  email_action_type: string;
  site_url: string;
}

const ACTION_LABEL: Record<string, string> = {
  signup: "confirm your email",
  magiclink: "sign in",
  recovery: "reset your password",
  invite: "accept your invite",
  email_change: "confirm your new email",
};

function buildHtml(d: EmailData, verifyUrl: string): string {
  const label = ACTION_LABEL[d.email_action_type] ?? "continue";
  return `
<div style="font-family: -apple-system, Segoe UI, Roboto, sans-serif; max-width: 440px; margin: 0 auto; padding: 24px;">
  <h2 style="color: #0d7377; margin-bottom: 4px;">Vamo</h2>
  <p style="color: #666; margin-top: 0;">Si va?</p>

  <p>Your code to ${label}:</p>
  <p style="font-size: 34px; font-weight: 700; letter-spacing: 8px; color: #0d7377; margin: 12px 0;">
    ${d.token}
  </p>
  <p>Type it into the app.</p>

  <p style="margin-top: 24px; color: #666;">
    Reading this on your phone? You can also
    <a href="${verifyUrl}" style="color: #0d7377;">tap here to ${label} directly</a>.
  </p>

  <p style="color: #999; font-size: 12px; margin-top: 32px;">
    The code and link expire in 1 hour and work only once.
    If you didn't request this, you can ignore this email.
  </p>
</div>`;
}

Deno.serve(async (req) => {
  try {
    const payload = await req.text();
    const headers = Object.fromEntries(req.headers);

    // Verify the request really comes from Supabase Auth.
    const wh = new Webhook(HOOK_SECRET);
    const { user, email_data } = wh.verify(payload, headers) as {
      user: { email: string };
      email_data: EmailData;
    };

    const verifyUrl = `${email_data.site_url}/auth/v1/verify` +
      `?token=${email_data.token_hash}` +
      `&type=${email_data.email_action_type}` +
      `&redirect_to=${encodeURIComponent(email_data.redirect_to)}`;

    const sendResult = await sendAuthEmailWithFallback({
      to: user.email,
      subject: `Your Vamo code: ${email_data.token}`,
      html: buildHtml(email_data, verifyUrl),
    }, buildEmailProviderConfig());

    if (sendResult.ok) {
      if (sendResult.provider !== "brevo") {
        console.warn("Auth email sent via fallback provider:", {
          provider: sendResult.provider,
          attempts: summarizeAttempts(sendResult.attempts),
        });
      }
      return new Response("{}", {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }

    console.error("Auth email send failed:", {
      attempts: summarizeAttempts(sendResult.attempts),
    });
    return new Response(
      JSON.stringify({
        error: { http_code: 500, message: "Email send failed" },
      }),
      { status: 500, headers: { "content-type": "application/json" } },
    );
  } catch (err) {
    console.error("Hook error:", err);
    return new Response(
      JSON.stringify({
        error: { http_code: 401, message: "Invalid hook payload" },
      }),
      { status: 401, headers: { "content-type": "application/json" } },
    );
  }
});

function summarizeAttempts(
  attempts: Array<{
    provider: string;
    configured: boolean;
    ok: boolean;
    status?: number;
    detail?: string;
  }>,
) {
  return attempts.map((attempt) => ({
    provider: attempt.provider,
    configured: attempt.configured,
    ok: attempt.ok,
    status: attempt.status,
    detail: attempt.detail,
  }));
}
