import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import {
  readableAdminAccessFailure,
  requireIngestionAdminPrincipal,
} from "@/lib/ingestion-admin-auth";

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
          TOTP challenge UI is the next slice. The server already blocks command
          execution until Supabase reports an `aal2` session.
        </div>

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
