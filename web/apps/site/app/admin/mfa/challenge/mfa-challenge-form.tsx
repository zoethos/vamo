"use client";

import { useState, type FormEvent } from "react";

export function MfaChallengeForm({
  factorId,
  next,
}: {
  factorId: string;
  next: string;
}) {
  const [code, setCode] = useState("");
  const [status, setStatus] = useState<"idle" | "verifying">("idle");
  const [error, setError] = useState<string | undefined>();

  async function verifyChallenge(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setStatus("verifying");
    setError(undefined);

    const response = await fetch("/admin/mfa/challenge/verify", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ factorId, code, next }),
    });
    const payload = (await response.json().catch(() => null)) as
      | { ok?: boolean; next?: string; error?: string }
      | null;

    if (!response.ok || !payload?.ok || !payload.next) {
      setStatus("idle");
      setError(payload?.error ?? "The authenticator code could not be verified.");
      return;
    }

    window.location.assign(payload.next);
  }

  return (
    <form className="admin-auth-form" onSubmit={verifyChallenge}>
      <label htmlFor="admin-mfa-code">Authenticator code</label>
      <input
        id="admin-mfa-code"
        name="code"
        type="text"
        inputMode="numeric"
        pattern="[0-9 ]{6,8}"
        autoComplete="one-time-code"
        value={code}
        onChange={(event) => setCode(event.target.value)}
        placeholder="123456"
        required
      />

      <button type="submit" disabled={status === "verifying"}>
        {status === "verifying" ? "Verifying..." : "Verify and continue"}
      </button>

      {error ? (
        <div className="admin-auth-message admin-auth-message-danger" role="alert">
          {error}
        </div>
      ) : null}
    </form>
  );
}
