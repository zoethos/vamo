import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { getSupabasePublicConfig } from "@/lib/supabase-config";

export const metadata: Metadata = {
  title: "Admin sign-in · Vamo",
  robots: {
    index: false,
    follow: false,
  },
};

type SearchParams = {
  sent?: string;
  email?: string;
  error?: string;
  method?: string;
  next?: string;
  reason?: string;
};

type SignInMethod = "link" | "code";

export default async function AdminSignInPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  const isConfigured = Boolean(getSupabasePublicConfig());
  const next = normalizeNextPath(params.next);
  const sentEmail = params.email?.trim();
  const signInMethod = normalizeSignInMethod(params.method);
  const hasSentEmail = params.sent === "1" && Boolean(sentEmail);
  const showOtpForm = hasSentEmail && signInMethod === "code";
  const showMissingConfig = !isConfigured || params.reason === "auth_not_configured";
  const error = showMissingConfig && params.error === "auth_not_configured" ? undefined : params.error;

  return (
    <main className="admin-auth-page">
      <section className="admin-auth-panel" aria-labelledby="admin-sign-in-title">
        <Link className="admin-auth-brand" href="/">
          <Image src="/brand/primary_mark.png" alt="" width={36} height={36} priority />
          <span>Vamo admin</span>
        </Link>

        <div className="admin-auth-copy">
          <p className="admin-kicker">Protected operator console</p>
          <h1 id="admin-sign-in-title">Sign in to continue</h1>
          <p>
            First verify your email session. If MFA is required and your account
            is not enrolled yet, the next screen will guide you through the
            authenticator QR-code setup.
          </p>
        </div>

        {showMissingConfig ? (
          <div className="admin-auth-message admin-auth-message-danger" role="alert">
            Admin auth env vars are missing, so the dashboard is locked.
          </div>
        ) : null}

        {error ? (
          <div className="admin-auth-message admin-auth-message-danger" role="alert">
            {readableError(error)}
          </div>
        ) : null}

        {hasSentEmail ? (
          <div className="admin-auth-message" role="status">
            {sentMessage(signInMethod, sentEmail)}
          </div>
        ) : null}

        <form className="admin-auth-form" action="/admin/sign-in/request" method="post">
          <input type="hidden" name="next" value={next} />
          <label htmlFor="admin-email">Email</label>
          <input
            id="admin-email"
            name="email"
            type="email"
            autoComplete="email"
            required
            placeholder="you@company.com"
            defaultValue={sentEmail ?? ""}
            disabled={!isConfigured}
          />
          <fieldset className="admin-auth-methods" disabled={!isConfigured}>
            <legend>Choose sign-in method</legend>
            <label className="admin-auth-method">
              <input
                type="radio"
                name="method"
                value="link"
                defaultChecked={signInMethod === "link"}
              />
              <span>
                <strong>Email link</strong>
                <small>Open the secure link from the email.</small>
              </span>
            </label>
            <label className="admin-auth-method">
              <input
                type="radio"
                name="method"
                value="code"
                defaultChecked={signInMethod === "code"}
              />
              <span>
                <strong>Email one-time code</strong>
                <small>Enter the code from the same email. No authenticator app required yet.</small>
              </span>
            </label>
          </fieldset>
          <button type="submit" disabled={!isConfigured}>
            {hasSentEmail ? "Send another sign-in email" : "Send sign-in email"}
          </button>
        </form>

        {showOtpForm ? (
          <form
            className="admin-auth-form admin-auth-form-secondary"
            action="/admin/sign-in/verify"
            method="post"
          >
            <input type="hidden" name="next" value={next} />
            <input type="hidden" name="email" value={sentEmail} />
            <label htmlFor="admin-email-otp">Email one-time code</label>
            <input
              id="admin-email-otp"
              name="otp"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={12}
              required
              placeholder="123456"
              disabled={!isConfigured}
            />
            <button type="submit" disabled={!isConfigured}>
              Verify code
            </button>
          </form>
        ) : null}
      </section>
    </main>
  );
}

function normalizeNextPath(value: string | undefined): string {
  if (!value || !value.startsWith("/") || value.startsWith("//")) {
    return "/admin/ingestion";
  }
  return value;
}

function normalizeSignInMethod(value: string | undefined): SignInMethod {
  return value === "code" ? "code" : "link";
}

function sentMessage(method: SignInMethod, email: string | undefined): string {
  const suffix = email ? ` to ${email}` : "";
  if (method === "code") {
    return `Email code sent${suffix}. Enter the email one-time code below. Authenticator app setup happens after this email step, if required.`;
  }
  return `Email link sent${suffix}. Open the secure link in this browser. Authenticator app setup happens after this email step, if required.`;
}

function readableError(error: string): string {
  switch (error) {
    case "missing_email":
      return "Enter an admin email address.";
    case "auth_not_configured":
      return "Supabase auth is not configured for this environment.";
    case "callback_failed":
      return "The sign-in link could not be verified. Request a new link.";
    case "send_failed":
      return "The sign-in link could not be sent. Check the email address and try again.";
    case "rate_limited":
      return "Too many sign-in links were requested. Wait a little, then try again.";
    case "otp_missing":
      return "Enter the email one-time code from your sign-in email.";
    case "otp_failed":
      return "The email one-time code could not be verified. Request a new sign-in email and try again.";
    case "not_authenticated":
      return "Sign in before opening the admin console.";
    default:
      return "Sign-in failed. Try again.";
  }
}
