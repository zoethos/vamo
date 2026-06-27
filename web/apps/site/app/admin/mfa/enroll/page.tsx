import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import {
  readableAdminAccessFailure,
  requireIngestionAdminPrincipal,
} from "@/lib/ingestion-admin-auth";
import { MfaEnrollForm } from "./mfa-enroll-form";

export const metadata: Metadata = {
  title: "Confluendo MFA enrollment",
  robots: {
    index: false,
    follow: false,
  },
};

type SearchParams = {
  next?: string;
};

export default async function AdminMfaEnrollPage({
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

  if (principal.hasVerifiedMfaFactor) {
    redirect(`/admin/mfa/challenge?next=${encodeURIComponent(next)}`);
  }

  return (
    <main className="admin-auth-page">
      <section className="admin-auth-panel" aria-labelledby="admin-mfa-enroll-title">
        <Link className="admin-auth-brand" href="/">
          <Image src="/brand/primary_mark.png" alt="" width={36} height={36} priority />
          <span>Confluendo admin</span>
        </Link>

        <div className="admin-auth-copy">
          <p className="admin-kicker">MFA required</p>
          <h1 id="admin-mfa-enroll-title">Enroll an authenticator app</h1>
          <p>{readableAdminAccessFailure("mfa_enrollment_required")}</p>
        </div>

        <div className="admin-auth-message" role="status">
          Scan the QR code with Google Authenticator, Microsoft Authenticator,
          1Password, Authy, iCloud Keychain, or another TOTP app.
        </div>

        <MfaEnrollForm next={next} />

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
