# Confluendo Supabase Auth Email Template

Owner: **Confluendo** (`confluendo.com`). Vamo is the first consumer project,
not the owner of this auth template.

Apply in:

`Supabase dashboard -> Authentication -> Emails -> Templates -> Magic Link`

## Subject

Paste this into the Supabase subject field:

```text
Your Confluendo sign-in link and code
```

## Body

Paste **only** the raw HTML from:

`docs/AUTH_EMAIL_TEMPLATE_BODY.html`

Do not paste this Markdown file into Supabase. It contains operator notes and
will render as visible email text if pasted into the template body.

## Why The Template Uses Both Link And Code

- Supabase sends one auth email for this flow. The admin UI must not present
  "link" and "code" as two separate delivery modes.
- The secure link is the primary path for operators who opened the email in the
  same browser.
- The email code is the fallback path for Outlook, SafeLinks, link scanners, and
  cross-device sign-in.
- The direct link uses `{{ .RedirectTo }}&token_hash={{ .TokenHash }}&type=email`
  instead of `{{ .ConfirmationURL }}` so the admin callback can verify the
  token hash without relying on a PKCE verifier cookie in the same browser.
- The app passes `emailRedirectTo` as a callback URL that already includes the
  desired `next` path, so appending `&token_hash=...&type=email` is expected.
- This email verifies the first factor (`aal1`). If the admin has MFA enabled,
  the next page asks for a separate six-digit authenticator-app code (`aal2`).
- Use this template in the `confluendo-control` Supabase project. Consumer
  wording belongs in project metadata or downstream dashboards.
