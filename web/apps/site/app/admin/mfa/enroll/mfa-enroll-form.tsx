"use client";

import { useState, type FormEvent } from "react";

type Enrollment = {
  factorId: string;
  qrCodeSvg: string;
  secret: string;
  uri: string;
};

type RequestState =
  | { status: "idle" }
  | { status: "starting" }
  | { status: "ready"; enrollment: Enrollment }
  | { status: "verifying"; enrollment: Enrollment }
  | { status: "error"; message: string; enrollment?: Enrollment };

export function MfaEnrollForm({ next }: { next: string }) {
  const [state, setState] = useState<RequestState>({ status: "idle" });
  const [code, setCode] = useState("");

  const enrollment =
    state.status === "ready" || state.status === "verifying"
      ? state.enrollment
      : state.status === "error"
        ? state.enrollment
        : undefined;
  const isStarting = state.status === "starting";
  const isVerifying = state.status === "verifying";

  async function startEnrollment() {
    setState({ status: "starting" });
    const response = await postJson("/admin/mfa/enroll/start", {
      next,
      friendlyName: deviceFriendlyName(),
    });

    if (!response.ok) {
      setState({ status: "error", message: response.error });
      return;
    }

    setState({
      status: "ready",
      enrollment: {
        factorId: response.factorId,
        qrCodeSvg: response.qrCodeSvg,
        secret: response.secret,
        uri: response.uri,
      },
    });
    setCode("");
  }

  async function verifyEnrollment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!enrollment) {
      return;
    }

    setState({ status: "verifying", enrollment });
    const response = await postJson("/admin/mfa/enroll/verify", {
      factorId: enrollment.factorId,
      code,
      next,
    });

    if (!response.ok) {
      setState({ status: "error", message: response.error, enrollment });
      return;
    }

    window.location.assign(response.next);
  }

  return (
    <div className="admin-mfa-flow">
      {!enrollment ? (
        <button
          className="admin-auth-primary-button"
          type="button"
          onClick={startEnrollment}
          disabled={isStarting}
        >
          {isStarting ? "Creating setup..." : "Create authenticator setup"}
        </button>
      ) : null}

      {enrollment ? (
        <form className="admin-auth-form" onSubmit={verifyEnrollment}>
          <div className="admin-mfa-qr" aria-label="Authenticator app QR code">
            <img
              src={`data:image/svg+xml;utf-8,${encodeURIComponent(enrollment.qrCodeSvg)}`}
              alt=""
            />
          </div>

          <label htmlFor="admin-mfa-secret">Manual setup key</label>
          <input
            id="admin-mfa-secret"
            className="admin-mfa-secret"
            type="text"
            value={enrollment.secret}
            readOnly
            spellCheck={false}
          />

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

          <button type="submit" disabled={isVerifying}>
            {isVerifying ? "Verifying..." : "Verify and continue"}
          </button>
        </form>
      ) : null}

      {state.status === "error" ? (
        <div className="admin-auth-message admin-auth-message-danger" role="alert">
          {state.message}
        </div>
      ) : null}
    </div>
  );
}

async function postJson(
  url: string,
  body: Record<string, string>
): Promise<
  | {
      ok: true;
      next: string;
      factorId: string;
      qrCodeSvg: string;
      secret: string;
      uri: string;
    }
  | { ok: false; error: string }
> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const payload = (await response.json().catch(() => null)) as
    | { ok?: boolean; error?: string }
    | null;

  if (!response.ok || !payload?.ok) {
    return {
      ok: false,
      error: payload?.error ?? "The MFA request failed. Try again.",
    };
  }

  return payload as {
    ok: true;
    next: string;
    factorId: string;
    qrCodeSvg: string;
    secret: string;
    uri: string;
  };
}

function deviceFriendlyName(): string {
  const platform = navigator.platform || "device";
  return `Vamo admin ${platform}`.slice(0, 64);
}
