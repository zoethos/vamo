import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ConfluendoMark } from "@/app/admin/confluendo-brand";
import { requireIngestionAdminPrincipal } from "@/lib/ingestion-admin-auth";
import { createSupabaseServerClient } from "@/lib/supabase-server";
import { MfaChallengeForm } from "./mfa-challenge-form";

export const metadata: Metadata = {
  title: "Operator MFA challenge · Confluendo",
  robots: {
    index: false,
    follow: false,
  },
};

type SearchParams = {
  reason?: string;
  next?: string;
};

export default async function AdminMfaChallengePage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  const next = normalizeNextPath(params.next);
  const principal = await requireIngestionAdminPrincipal({
    projectKey: "vamo",
    nextPath: next,
  });

  if (!principal.hasVerifiedMfaFactor) {
    redirect(`/admin/mfa/enroll?next=${encodeURIComponent(next)}`);
  }

  if (principal.assuranceLevel === "aal2" && params.reason !== "fresh_step_up_required") {
    redirect(next);
  }

  const supabase = await createSupabaseServerClient();
  const factors = await supabase?.auth.mfa.listFactors();
  const factorLookupFailed = !factors || Boolean(factors.error);
  const factorId = factors?.data?.totp[0]?.id;

  if (!factorLookupFailed && !factorId) {
    redirect(`/admin/mfa/enroll?next=${encodeURIComponent(next)}`);
  }

  return (
    <main className="admin-mfa-stepup-page">
      <section className="admin-mfa-stepup-card" aria-labelledby="admin-mfa-challenge-title">
        <div className="admin-mfa-stepup-spectrum" aria-hidden="true">
          <span />
          <span />
          <span />
          <span />
        </div>

        <div className="admin-mfa-stepup-inner">
          <div className="admin-mfa-stepup-header">
            <Link className="admin-mfa-stepup-brand" href="/admin/ingestion">
              <ConfluendoMark size={28} variant="spectrum" />
              <span>Confluendo</span>
            </Link>
            <div className="admin-mfa-stepup-session" aria-label="Current session requires MFA step-up">
              <span aria-hidden="true" />
              <strong>aal1 · step-up required</strong>
            </div>
          </div>

          <div className="admin-mfa-stepup-copy">
            <p className="admin-mfa-stepup-kicker">Step 2 · authenticator app</p>
            <h1 id="admin-mfa-challenge-title">Verify before continuing</h1>
            <p>
              Your email link or email code verified the first step. Operator
              controls also require the current six-digit code from your
              authenticator app. Do not use the eight-digit email code here.
            </p>
          </div>

          {factorLookupFailed || !factorId ? (
            <div className="admin-mfa-stepup-message admin-mfa-stepup-message-danger" role="alert">
              Supabase MFA factors could not be loaded. Refresh this page before
              using operator controls.
            </div>
          ) : (
            <MfaChallengeForm factorId={factorId} next={next} />
          )}

          <div className="admin-mfa-stepup-actions">
            <Link href={next}>Back to console</Link>
            <Link href="/admin/sign-out">Sign out</Link>
          </div>

          <div className="admin-mfa-stepup-footer">
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path d="M12 2 4 5v6c0 5 3.5 8 8 11 4.5-3 8-6 8-11V5l-8-3Z" />
            </svg>
            <span>audit-logged · session elevated to aal2 on success</span>
          </div>
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
