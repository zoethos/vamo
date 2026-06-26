import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import {
  readableAdminAccessFailure,
  requireIngestionAdminPrincipal,
} from "@/lib/ingestion-admin-auth";
import { createSupabaseServerClient } from "@/lib/supabase-server";
import { MfaChallengeForm } from "./mfa-challenge-form";

export const metadata: Metadata = {
  title: "Admin MFA challenge · Vamo",
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
    <main className="admin-auth-page">
      <section className="admin-auth-panel" aria-labelledby="admin-mfa-challenge-title">
        <Link className="admin-auth-brand" href="/">
          <Image src="/brand/primary_mark.png" alt="" width={36} height={36} priority />
          <span>Vamo admin</span>
        </Link>

        <div className="admin-auth-copy">
          <p className="admin-kicker">MFA step-up</p>
          <h1 id="admin-mfa-challenge-title">Verify before continuing</h1>
          <p>
            {readableAdminAccessFailure(params.reason ?? "mfa_challenge_required")}
          </p>
        </div>

        <div className="admin-auth-message" role="status">
          Enter the current six-digit code from your authenticator app. Reset
          actions require a fresh verification.
        </div>

        {factorLookupFailed || !factorId ? (
          <div className="admin-auth-message admin-auth-message-danger" role="alert">
            Supabase MFA factors could not be loaded. Refresh this page before
            using operator controls.
          </div>
        ) : (
          <MfaChallengeForm factorId={factorId} next={next} />
        )}

        <div className="admin-auth-actions">
          <Link href="/admin/sign-out">Sign out</Link>
          <Link href={next}>Back to console</Link>
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
