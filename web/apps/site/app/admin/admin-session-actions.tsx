"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import type { AdminPrincipal } from "@vamo/ingestion-platform/admin-auth";

type AdminSessionActionsProps = {
  principal: Pick<AdminPrincipal, "assuranceLevel" | "email" | "role">;
  freshStepUpExpiresAt?: string;
  mfaChallengeHref?: string;
  serverNowMs?: number;
};

export function AdminSessionActions({
  principal,
  freshStepUpExpiresAt,
  mfaChallengeHref = "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion",
  serverNowMs = Date.now()
}: AdminSessionActionsProps) {
  const email = principal.email || "Signed in";
  const expiresAtMs = useMemo(
    () => (freshStepUpExpiresAt ? Date.parse(freshStepUpExpiresAt) : Number.NaN),
    [freshStepUpExpiresAt]
  );
  const [nowMs, setNowMs] = useState(serverNowMs);

  useEffect(() => {
    if (!Number.isFinite(expiresAtMs)) {
      return undefined;
    }
    const interval = window.setInterval(() => setNowMs(Date.now()), 1000);
    return () => window.clearInterval(interval);
  }, [expiresAtMs]);

  const remainingMs = Number.isFinite(expiresAtMs) ? Math.max(0, expiresAtMs - nowMs) : undefined;
  const isExpired = remainingMs !== undefined && remainingMs <= 0;

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
      {remainingMs !== undefined ? (
        <Link
          className={`admin-stepup-timer${isExpired ? " admin-stepup-expired" : ""}`}
          href={mfaChallengeHref}
          title="Refresh the short MFA window required for staging-canary approval"
        >
          <span>{isExpired ? "Step-up expired" : "Step-up"}</span>
          <strong>{isExpired ? "Refresh MFA" : formatRemaining(remainingMs)}</strong>
        </Link>
      ) : null}
      <Link className="admin-logout-button" href="/admin/sign-out">
        Sign out
      </Link>
    </div>
  );
}

function formatRemaining(remainingMs: number): string {
  const totalSeconds = Math.max(0, Math.ceil(remainingMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}
