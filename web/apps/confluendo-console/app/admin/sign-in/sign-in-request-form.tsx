"use client";

import { useState } from "react";

type SignInRequestFormProps = {
  initialEmail: string;
  isConfigured: boolean;
  hasSentEmail: boolean;
  next: string;
};

export function SignInRequestForm({
  initialEmail,
  isConfigured,
  hasSentEmail,
  next,
}: SignInRequestFormProps) {
  const [email, setEmail] = useState(initialEmail);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const emailValid = /.+@.+\..+/.test(email);
  const disabled = !isConfigured || isSubmitting;

  return (
    <form
      className="admin-sign-in-request-form"
      action="/admin/sign-in/request"
      method="post"
      onSubmit={() => setIsSubmitting(true)}
      aria-busy={isSubmitting}
    >
      <input type="hidden" name="next" value={next} />
      <input type="hidden" name="email" value={email} />
      <input type="hidden" name="method" value="link" />

      <label htmlFor="admin-email">Work email</label>
      <div className="admin-sign-in-input-shell">
        <MailIcon />
        <input
          id="admin-email"
          type="email"
          autoComplete="email"
          required
          placeholder="you@company.com"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          disabled={disabled}
        />
        {emailValid && !isSubmitting ? <CheckIcon /> : null}
      </div>

      <div className="admin-sign-in-email-flow">
        <b>One email, two verification options</b>
        <span>
          The email includes a secure link and an 8-digit fallback code. Use
          either one to verify your email session.
        </span>
      </div>

      <button className="admin-sign-in-primary-button" type="submit" disabled={disabled}>
        {isSubmitting ? "Sending..." : primaryLabel(hasSentEmail)}
        <ArrowIcon />
      </button>
      {isSubmitting ? (
        <p className="admin-sign-in-submit-status" role="status">
          Sending the operator sign-in email. Keep this window open.
        </p>
      ) : null}
    </form>
  );
}

function primaryLabel(hasSentEmail: boolean): string {
  return hasSentEmail ? "Send another sign-in email" : "Send sign-in email";
}

function MailIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="m4 7 8 6 8-6" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M20 6 9 17l-5-5" />
    </svg>
  );
}

function ArrowIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M5 12h14" />
      <path d="m13 6 6 6-6 6" />
    </svg>
  );
}
