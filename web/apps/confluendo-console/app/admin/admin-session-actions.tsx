"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import type { AdminPrincipal } from "@confluendo/ingestion-platform/admin-auth";

type AdminSessionActionsProps = {
  principal: Pick<AdminPrincipal, "assuranceLevel" | "email" | "role">;
  freshStepUpExpiresAt?: string;
  mfaChallengeHref?: string;
  serverNowMs?: number;
};

const RENEWAL_WARNING_MS = 5 * 60 * 1000;

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
  const needsRenewal =
    remainingMs !== undefined && (isExpired || remainingMs <= RENEWAL_WARNING_MS);
  const mfaStatus = isExpired
    ? "MFA renewal required"
    : needsRenewal
      ? "Renew MFA soon"
      : "MFA active";
  const mfaAction = isExpired
    ? "Renew now"
    : needsRenewal
      ? `Renew now · ${formatRemaining(remainingMs ?? 0)}`
      : `${formatRemaining(remainingMs ?? 0)} remaining`;

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
          className={`admin-stepup-timer${needsRenewal ? " admin-stepup-renewal" : ""}${
            isExpired ? " admin-stepup-expired" : ""
          }`}
          href={mfaChallengeHref}
          aria-label={`${mfaStatus}. ${
            isExpired
              ? "Renew now with your authenticator app."
              : "Select to renew early with your authenticator app."
          } You remain signed in to the console.`}
          title="You remain signed in. Renewing opens the authenticator check only; it does not send a new email sign-in link."
        >
          <span>{mfaStatus}</span>
          <strong>{mfaAction}</strong>
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
