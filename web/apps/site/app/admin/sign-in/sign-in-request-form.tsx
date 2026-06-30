"use client";

import { useState } from "react";
import type { SignInMethod } from "./page";

type SignInRequestFormProps = {
  initialEmail: string;
  initialMethod: SignInMethod;
  isConfigured: boolean;
  hasSentEmail: boolean;
  next: string;
};

const signInMethods: Array<{
  id: SignInMethod;
  icon: "link" | "pin";
  title: string;
  description: string;
}> = [
  {
    id: "link",
    icon: "link",
    title: "Email sign-in link",
    description: "Send a secure link only if this email is already provisioned.",
  },
  {
    id: "code",
    icon: "pin",
    title: "Email one-time code",
    description: "Send an email code only if this admin account already exists.",
  },
];

export function SignInRequestForm({
  initialEmail,
  initialMethod,
  isConfigured,
  hasSentEmail,
  next,
}: SignInRequestFormProps) {
  const [method, setMethod] = useState<SignInMethod>(initialMethod);
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

      <label htmlFor="admin-email">Work email</label>
      <div className="admin-sign-in-input-shell">
        <MailIcon />
        <input
          id="admin-email"
          name="email"
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

      <fieldset className="admin-sign-in-methods" disabled={disabled}>
        <legend>Choose sign-in method</legend>
        <div>
          {signInMethods.map((item) => {
            const selected = method === item.id;
            return (
              <label
                key={item.id}
                className="admin-sign-in-method"
                data-selected={selected ? "true" : "false"}
              >
                <input
                  type="radio"
                  name="method"
                  value={item.id}
                  checked={selected}
                  onChange={() => setMethod(item.id)}
                />
                <span className="admin-sign-in-radio" aria-hidden="true">
                  <i />
                </span>
                <span className="admin-sign-in-method-copy">
                  <b>
                    {item.icon === "link" ? <LinkIcon /> : <PinIcon />}
                    {item.title}
                  </b>
                  <small>{item.description}</small>
                </span>
              </label>
            );
          })}
        </div>
      </fieldset>

      <button className="admin-sign-in-primary-button" type="submit" disabled={disabled}>
        {isSubmitting ? "Sending..." : primaryLabel(method, hasSentEmail)}
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

function primaryLabel(method: SignInMethod, hasSentEmail: boolean): string {
  if (method === "code") {
    return hasSentEmail ? "Send another one-time code" : "Send one-time code";
  }
  return hasSentEmail ? "Send another sign-in link" : "Send sign-in link";
}

function MailIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="m4 7 8 6 8-6" />
    </svg>
  );
}

function LinkIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M10 13a5 5 0 0 0 7.1.1l2-2a5 5 0 0 0-7.1-7.1l-1.1 1.1" />
      <path d="M14 11a5 5 0 0 0-7.1-.1l-2 2a5 5 0 0 0 7.1 7.1l1.1-1.1" />
    </svg>
  );
}

function PinIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="4" y="4" width="16" height="16" rx="4" />
      <path d="M8 9h.01M12 9h.01M16 9h.01M8 15h.01M12 15h.01M16 15h.01" />
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
