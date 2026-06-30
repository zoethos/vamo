"use client";

import {
  useRef,
  useState,
  type ClipboardEvent,
  type FormEvent,
  type KeyboardEvent,
} from "react";

const CODE_LENGTH = 6;
const EMPTY_DIGITS = Array.from({ length: CODE_LENGTH }, () => "");

export function MfaChallengeForm({
  factorId,
  next,
}: {
  factorId: string;
  next: string;
}) {
  const [digits, setDigits] = useState<string[]>(EMPTY_DIGITS);
  const [status, setStatus] = useState<"idle" | "verifying">("idle");
  const [error, setError] = useState<string | undefined>();
  const [hint, setHint] = useState<string | undefined>();
  const inputRefs = useRef<Array<HTMLInputElement | null>>([]);
  const code = digits.join("");

  async function verifyChallenge(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!/^\d{6}$/.test(code)) {
      setHint("enter all 6 digits");
      setError(undefined);
      focusFirstEmptyDigit();
      return;
    }

    setStatus("verifying");
    setError(undefined);
    setHint("verifying...");

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
      setHint("try again");
      setError(payload?.error ?? "The authenticator code could not be verified.");
      return;
    }

    window.location.assign(payload.next);
  }

  function handleInput(index: number, value: string) {
    const cleanValue = value.replace(/\D/g, "");

    if (cleanValue.length > 1) {
      applyDigits(index, cleanValue);
      return;
    }

    const nextDigits = [...digits];
    nextDigits[index] = cleanValue;
    setDigits(nextDigits);
    setHint(undefined);
    setError(undefined);

    if (cleanValue && index < CODE_LENGTH - 1) {
      inputRefs.current[index + 1]?.focus();
    }
  }

  function handlePaste(index: number, event: ClipboardEvent<HTMLInputElement>) {
    event.preventDefault();
    applyDigits(index, event.clipboardData.getData("text"));
  }

  function handleKeyDown(index: number, event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "Backspace" && !digits[index] && index > 0) {
      inputRefs.current[index - 1]?.focus();
      return;
    }

    if (event.key === "ArrowLeft" && index > 0) {
      event.preventDefault();
      inputRefs.current[index - 1]?.focus();
      return;
    }

    if (event.key === "ArrowRight" && index < CODE_LENGTH - 1) {
      event.preventDefault();
      inputRefs.current[index + 1]?.focus();
    }
  }

  function applyDigits(index: number, value: string) {
    const pastedDigits = value.replace(/\D/g, "").slice(0, CODE_LENGTH - index);
    if (!pastedDigits) {
      return;
    }

    const nextDigits = [...digits];
    for (let offset = 0; offset < pastedDigits.length; offset += 1) {
      nextDigits[index + offset] = pastedDigits[offset];
    }
    setDigits(nextDigits);
    setHint(undefined);
    setError(undefined);

    const nextFocus = Math.min(index + pastedDigits.length, CODE_LENGTH - 1);
    inputRefs.current[nextFocus]?.focus();
  }

  function focusFirstEmptyDigit() {
    const firstEmpty = digits.findIndex((digit) => !digit);
    inputRefs.current[firstEmpty === -1 ? CODE_LENGTH - 1 : firstEmpty]?.focus();
  }

  const statusText = hint ?? (code.length === CODE_LENGTH ? "ready" : "");
  const statusClass =
    error || hint === "enter all 6 digits" || hint === "try again"
      ? "admin-mfa-code-status admin-mfa-code-status-warning"
      : "admin-mfa-code-status";

  return (
    <form className="admin-mfa-stepup-form" onSubmit={verifyChallenge}>
      <input type="hidden" name="code" value={code} />

      <div className="admin-mfa-code-row">
        <label id="admin-mfa-code-label">Authenticator code</label>
        <span className={statusClass} role={statusText ? "status" : undefined}>
          {statusText}
        </span>
      </div>

      <div
        className="admin-mfa-otp-grid"
        role="group"
        aria-labelledby="admin-mfa-code-label"
      >
        {digits.map((digit, index) => (
          <input
            key={`mfa-digit-${index}`}
            ref={(element) => {
              inputRefs.current[index] = element;
            }}
            className="admin-mfa-otp-input"
            type="text"
            inputMode="numeric"
            pattern="[0-9]*"
            autoComplete={index === 0 ? "one-time-code" : "off"}
            maxLength={1}
            value={digit}
            onChange={(event) => handleInput(index, event.currentTarget.value)}
            onPaste={(event) => handlePaste(index, event)}
            onKeyDown={(event) => handleKeyDown(index, event)}
            aria-label={`Digit ${index + 1} of ${CODE_LENGTH}`}
            placeholder="•"
            disabled={status === "verifying"}
          />
        ))}
      </div>

      <button className="admin-mfa-stepup-submit" type="submit" disabled={status === "verifying"}>
        {status === "verifying" ? "Verifying..." : "Verify and continue"}
      </button>

      {error ? (
        <div className="admin-mfa-stepup-message admin-mfa-stepup-message-danger" role="alert">
          {error}
        </div>
      ) : null}
    </form>
  );
}
