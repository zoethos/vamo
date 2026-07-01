import type { Metadata } from "next";
import Link from "next/link";
import { ConfluendoMark } from "@/app/admin/confluendo-brand";
import { readableAdminAccessFailure } from "@/lib/ingestion-admin-auth";

export const metadata: Metadata = {
  title: "Operator access denied · Confluendo",
  robots: {
    index: false,
    follow: false,
  },
};

type SearchParams = {
  reason?: string;
  next?: string;
};

export default async function AdminAccessDeniedPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;

  return (
    <main className="admin-auth-page">
      <section className="admin-auth-panel" aria-labelledby="admin-access-title">
        <Link className="admin-auth-brand" href="/admin/ingestion">
          <ConfluendoMark size={34} />
          <span>Confluendo</span>
        </Link>

        <div className="admin-auth-copy">
          <p className="admin-kicker">Protected operator console</p>
          <h1 id="admin-access-title">Access denied</h1>
          <p>{readableAdminAccessFailure(params.reason ?? "")}</p>
        </div>

        <div className="admin-auth-actions">
          <Link href="/admin/sign-out">Sign out</Link>
          <Link href={normalizeNextPath(params.next)}>Try again</Link>
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
