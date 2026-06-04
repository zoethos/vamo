# Supabase auth email template — Magic Link with OTP code

Why: the default Supabase template sends only a link. Links break for Outlook
users (SafeLinks rewrites and pre-consumes them) and for anyone reading email
on a different device than the phone. The app's auth screen already accepts a
6-digit code (`verifyOtp`), so the email must carry `{{ .Token }}`.

Apply in: **Supabase dashboard → Authentication → Email Templates → Magic Link**

## Subject

```
Your Vamo code: {{ .Token }}
```

(Code in the subject = visible in the notification without opening the email.)

## Body (HTML)

```html
<div style="font-family: -apple-system, Segoe UI, Roboto, sans-serif; max-width: 440px; margin: 0 auto; padding: 24px;">
  <h2 style="color: #0d7377; margin-bottom: 4px;">Vamo</h2>
  <p style="color: #666; margin-top: 0;">Si va?</p>

  <p>Your sign-in code:</p>
  <p style="font-size: 34px; font-weight: 700; letter-spacing: 8px; color: #0d7377; margin: 12px 0;">
    {{ .Token }}
  </p>
  <p>Type it into the app.</p>
  <p style="color: #666; font-size: 14px;">
    Opened this email on a different device than where you entered your email?
    Use the code above — it works everywhere. The tap-to-sign-in link only works
    on the same device where you started sign-in.
  </p>

  <p style="margin-top: 24px; color: #666;">
    Reading this on your phone? You can also
    <a href="{{ .ConfirmationURL }}" style="color: #0d7377;">tap here to sign in directly</a>.
  </p>

  <p style="color: #999; font-size: 12px; margin-top: 32px;">
    The code and link expire in 1 hour and work only once.
    If you didn't request this, you can ignore this email.
  </p>
</div>
```

## Notes

- The **code path** is the reliable one: immune to SafeLinks, device mismatch,
  and link prefetching. PKCE magic links are bound to the device that requested
  them — the 6-digit code is the only cross-device sign-in path. The link stays
  as a convenience when you read email on the same device where you started
  sign-in.
- Same `{{ .Token }}` approach applies to the **Confirm signup** and **Email
  change** templates if those flows are enabled later.
- Before testers arrive: configure **custom SMTP** (Settings → Auth → SMTP;
  e.g. Resend free tier) — the built-in email service is rate-limited to a few
  messages per hour and not meant for production.
