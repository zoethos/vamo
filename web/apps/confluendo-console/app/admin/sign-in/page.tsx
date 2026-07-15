import type { Metadata } from "next";
import type { ReactNode } from "react";
import Link from "next/link";
import { ConfluendoMark } from "@/app/admin/confluendo-brand";
import { ControlEnvironmentSwitcher } from "@/app/admin/control-environment-switcher";
import { CONTROL_ENVIRONMENTS } from "@/lib/control-environment";
import { getControlEnvironmentConfig } from "@/lib/control-environment-config";
import { getActiveControlEnvironmentConfig } from "@/lib/control-environment-server";
import { getSupabasePublicConfig } from "@/lib/supabase-config";
import { SignInRequestForm } from "./sign-in-request-form";

export const metadata: Metadata = {
  title: "Operator sign-in · Confluendo",
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

export default async function AdminSignInPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  const isConfigured = Boolean(await getSupabasePublicConfig());
  const activeEnvironment = (await getActiveControlEnvironmentConfig())?.environment ?? "production";
  const availableControlEnvironments = CONTROL_ENVIRONMENTS.filter((environment) =>
    Boolean(getControlEnvironmentConfig(environment))
  );
  const next = normalizeNextPath(params.next);
  const sentEmail = params.email?.trim();
  const hasSentEmail = params.sent === "1" && Boolean(sentEmail);
  const showOtpForm = hasSentEmail;
  const showMissingConfig = !isConfigured;
  const error =
    params.error === "auth_not_configured" || params.reason === "auth_not_configured"
      ? undefined
      : params.error;

  return (
    <main className="admin-sign-in-page">
      <section className="admin-sign-in-brand-panel" aria-label="Confluendo operator security">
        <RouteMotif />

        <Link className="admin-sign-in-brand" href="/admin/ingestion">
          <ConfluendoMark className="admin-sign-in-brand-mark" variant="spectrum" />
          <span className="admin-sign-in-brand-name">Confluendo</span>
          <span className="admin-sign-in-brand-badge">Operator</span>
        </Link>

        <div className="admin-sign-in-brand-copy">
          <p className="admin-sign-in-status-kicker">
            <span aria-hidden="true" />
            Operator console · EU-West
          </p>
          <h2>Every source, one current — governed end to end.</h2>
          <p>
            Confluendo turns external data into operational, governed ingestion.
            Every operator session is verified, time-boxed, and logged. Only
            provisioned admin accounts can request access.
          </p>
        </div>

        <div className="admin-sign-in-trust-list" aria-label="Security guarantees">
          <TrustRow icon={<LockIcon />} label="Provisioned admin accounts only" />
          <TrustRow icon={<VerifiedIcon />} label="MFA enforced with authenticator step-up" />
          <TrustRow icon={<AuditIcon />} label="Full audit trail on every action" />
        </div>

        <div className="admin-sign-in-panel-footer">
          <span>
            <i aria-hidden="true" />
            All systems operational
          </span>
          <span>© 2026 Confluendo</span>
        </div>
      </section>

      <section className="admin-sign-in-form-column" aria-labelledby="admin-sign-in-title">
        <div className="admin-sign-in-form-wrap">
          <p className="admin-sign-in-console-label">
            <ShieldIcon />
            Protected operator console
          </p>

          <div className="admin-sign-in-copy">
            <ControlEnvironmentSwitcher
              activeEnvironment={activeEnvironment}
              availableEnvironments={availableControlEnvironments}
              nextPath="/admin/sign-in"
            />
            <h1 id="admin-sign-in-title">Sign in to continue</h1>
            <p>
              Use an existing admin account. This console never creates accounts
              from sign-in requests; MFA setup happens after email verification
              if your account needs it.
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
              {sentMessage(sentEmail)}
            </div>
          ) : null}

          <SignInRequestForm
            initialEmail={sentEmail ?? ""}
            isConfigured={isConfigured}
            hasSentEmail={hasSentEmail}
            next={next}
          />

          {showOtpForm ? (
            <form
              className="admin-sign-in-verify-form"
              action="/admin/sign-in/verify"
              method="post"
            >
              <input type="hidden" name="next" value={next} />
              <input type="hidden" name="email" value={sentEmail} />
              <label htmlFor="admin-email-otp">Email one-time code</label>
              <div className="admin-sign-in-input-shell">
                <PinIcon />
                <input
                  id="admin-email-otp"
                  name="otp"
                  type="text"
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  minLength={8}
                  maxLength={8}
                  pattern="[0-9]{8}"
                  required
                  placeholder="12345678"
                  disabled={!isConfigured}
                />
              </div>
              <button type="submit" disabled={!isConfigured}>
                Verify code
                <ArrowIcon />
              </button>
            </form>
          ) : null}

          <p className="admin-sign-in-session-note">
            <LockIcon />
            Encrypted session · expires after 10 minutes of inactivity
          </p>
        </div>
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

function sentMessage(email: string | undefined): string {
  const suffix = email ? ` to ${email}` : "";
  return `Sign-in email sent${suffix}. Open the secure link, or enter the 8-digit email code below. This verifies your email session; if your account requires MFA, the next step is your authenticator app.`;
}

function readableError(error: string): string {
  switch (error) {
    case "missing_email":
      return "Enter an admin email address.";
    case "auth_not_configured":
      return "Supabase auth is not configured for this environment.";
    case "callback_failed":
      return "The direct sign-in link could not be verified automatically. Enter the 8-digit email code from that email, or request a fresh email if needed.";
    case "link_session_mismatch":
      return "That sign-in link was opened after its browser session expired or in a different browser. Request an email one-time code, or open a fresh link in this same browser.";
    case "send_failed":
      return "The sign-in email could not be sent. Use a provisioned admin account and try again.";
    case "rate_limited":
      return "Too many sign-in links were requested. Wait a little, then try again.";
    case "otp_missing":
      return "Enter the 8-digit email code from your sign-in email.";
    case "otp_failed":
      return "The email one-time code could not be verified. Request a new sign-in email and try again.";
    case "not_authenticated":
      return "Sign in before opening the admin console.";
    default:
      return "Sign-in failed. Try again.";
  }
}

function TrustRow({ icon, label }: { icon: ReactNode; label: string }) {
  return (
    <div className="admin-sign-in-trust-row">
      <span aria-hidden="true">{icon}</span>
      <p>{label}</p>
    </div>
  );
}

function RouteMotif() {
  return (
    <svg
      className="admin-sign-in-route-motif"
      viewBox="0 0 520 820"
      preserveAspectRatio="xMidYMid slice"
      aria-hidden="true"
    >
      <path d="M-20 640 C120 560 90 420 250 380 C400 344 410 210 540 150" />
      <circle cx="70" cy="600" r="4" />
      <circle cx="250" cy="380" r="5" />
      <circle cx="430" cy="188" r="4" />
    </svg>
  );
}

function ShieldIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 3 19 6v5c0 4.4-2.8 8.5-7 10-4.2-1.5-7-5.6-7-10V6l7-3Z" />
      <path d="m9 12 2 2 4-5" />
    </svg>
  );
}

function LockIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="5" y="10" width="14" height="10" rx="2" />
      <path d="M8 10V8a4 4 0 0 1 8 0v2" />
    </svg>
  );
}

function VerifiedIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="m12 3 2 2.2 3-.4.8 2.9 2.7 1.3-1.3 2.7 1.3 2.7-2.7 1.3-.8 2.9-3-.4L12 21l-2-2.2-3 .4-.8-2.9-2.7-1.3 1.3-2.7-1.3-2.7 2.7-1.3.8-2.9 3 .4L12 3Z" />
      <path d="m8.7 12 2.1 2.1 4.5-4.6" />
    </svg>
  );
}

function AuditIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M5 5h9" />
      <path d="M5 10h7" />
      <path d="M5 15h5" />
      <circle cx="16" cy="15" r="3" />
      <path d="m18.2 17.2 2.3 2.3" />
    </svg>
  );
}

function PinIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="4" y="4" width="16" height="16" rx="4" />
      <path d="M8 9h.01M12 9h.01M16 9h.01M8 15h.01M12 15h.01M16 15h.01" />
    </svg>
  );
}

function ArrowIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M5 12h14" />
      <path d="m13 6 6 6-6 6" />
    </svg>
  );
}
