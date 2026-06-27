# Confluendo Supabase auth email template — Magic Link with OTP code

Why: the default Supabase template sends only a link. Links break for Outlook
users (SafeLinks rewrites and pre-consumes them) and for anyone reading email
on a different device than the web console. Confluendo's operator auth screen
accepts a 6-digit code (`verifyOtp`), so the email must carry `{{ .Token }}`.

Owner: **Confluendo** (`confluendo.com`). Vamo is the first consumer/project
context, not the owner of this auth template.

Apply in: **Supabase dashboard → Authentication → Emails → Templates → Magic Link**

## Subject

```
Your Confluendo code: {{ .Token }}
```

(Code in the subject = visible in the notification without opening the email.)

## Body (HTML)

```html
<div style="font-family: -apple-system, Segoe UI, Roboto, sans-serif; max-width: 440px; margin: 0 auto; padding: 24px;">
  <h2 style="color: #0d7377; margin-bottom: 4px;">Confluendo</h2>
  <p style="color: #666; margin-top: 0;">Ingestion control for approved operator projects.</p>

  <p>Your Confluendo sign-in code:</p>
  <p style="font-size: 34px; font-weight: 700; letter-spacing: 8px; color: #0d7377; margin: 12px 0;">
    {{ .Token }}
  </p>
  <p>Type it into the operator console.</p>
  <p style="color: #666; font-size: 14px;">
    Opened this email on a different device than where you entered your email?
    Use the code above — it works everywhere. The tap-to-sign-in link below uses
    a server-verified token hash and works without a PKCE browser cookie.
  </p>

  <p style="margin-top: 24px; color: #666;">
    Reading this on your phone? You can also
    <a href="{{ .RedirectTo }}&token_hash={{ .TokenHash }}&type=email" style="color: #0d7377;">tap here to sign in directly</a>.
  </p>

  <p style="color: #666; font-size: 14px;">
    If you are opening this for Vamo, Confluendo is the ingestion platform that
    powers the Vamo control-plane instance.
  </p>

  <p style="color: #999; font-size: 12px; margin-top: 32px;">
    The code and link expire in 1 hour and work only once.
    If you didn't request this, you can ignore this email.
  </p>
</div>
```

## Notes

- The **code path** is still the most reliable one: immune to SafeLinks, device
  mismatch, and link prefetching.
- The direct link intentionally uses `{{ .RedirectTo }}` plus
  `token_hash={{ .TokenHash }}&type=email` instead of `{{ .ConfirmationURL }}`.
  `{{ .ConfirmationURL }}` can return a PKCE `code` that requires the same
  browser-side verifier cookie that requested the email. The admin callback
  route supports token-hash verification directly, which is less fragile for
  Outlook, link scanners, and multi-browser workflows.
- The app passes `emailRedirectTo` as a callback URL that already contains the
  desired `next` path, so appending `&token_hash=...&type=email` is expected.
- Same `{{ .Token }}` approach applies to the **Confirm signup** and **Email
  change** templates if those flows are enabled later.
- Use this template in the `confluendo-control` Supabase project. Vamo-specific
  wording belongs in project metadata or downstream dashboards, not in the
  Confluendo platform auth template.
- Before testers arrive: configure **custom SMTP** (Settings → Auth → SMTP;
  e.g. Resend free tier) — the built-in email service is rate-limited to a few
  messages per hour and not meant for production.
