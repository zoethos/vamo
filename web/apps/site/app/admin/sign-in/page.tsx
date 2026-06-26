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
  next?: string;
  reason?: string;
};

export default async function AdminSignInPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  const isConfigured = Boolean(getSupabasePublicConfig());
  const next = normalizeNextPath(params.next);
  const sentEmail = params.email?.trim();
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
            Admin dashboards require a verified Supabase session. Mutation
            controls remain disabled until allowlist and MFA gates are layered in.
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

        {params.sent === "1" ? (
          <div className="admin-auth-message" role="status">
            Magic link sent{sentEmail ? ` to ${sentEmail}` : ""}. Open it in this browser to continue.
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
            disabled={!isConfigured}
          />
          <button type="submit" disabled={!isConfigured}>
            Send magic link
          </button>
        </form>
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
    default:
      return "Sign-in failed. Try again.";
  }
}
