import Link from "next/link";
import type { AdminPrincipal } from "@vamo/ingestion-platform/admin-auth";

type AdminSessionActionsProps = {
  principal: Pick<AdminPrincipal, "assuranceLevel" | "email" | "role">;
};

export function AdminSessionActions({ principal }: AdminSessionActionsProps) {
  const email = principal.email || "Signed in";

  return (
    <div className="admin-session-actions" aria-label="Admin session">
      <div className="admin-user-chip" title={email}>
        <span className="admin-user-dot" aria-hidden="true" />
        <span className="admin-user-copy">
          <span>Signed in</span>
          <strong>{email}</strong>
          <small>
            {principal.role} · {principal.assuranceLevel}
          </small>
        </span>
      </div>
      <Link className="admin-logout-button" href="/admin/sign-out">
        Sign out
      </Link>
    </div>
  );
}
