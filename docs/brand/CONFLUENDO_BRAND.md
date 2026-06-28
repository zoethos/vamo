# Confluendo Brand

Confluendo is the **platform** — a reusable, governed ingestion engine that turns
external data into operational data. It is the brand worn by the platform-owned
operator surfaces (auth, admin, ingestion, provider control).

Vamo is a **consumer / project** of Confluendo, not the platform itself. Vamo
appears only as project or consumer context (e.g. the `vamo` project key, a
"Vamo project" label, or a "Back to Vamo" link to the consumer site). Vamo
branding never represents the platform.

> Positioning: *External data, made operational.*
> Tagline: **"Every source, one current."**

This file is the canonical, lightweight brand source. The bulky design-tool HTML
exports in `docs/brand/` (`Confluendo Brand*.html`, `Confluendo Logo - Colorful*.html`)
are generated reference artifacts and are intentionally not committed.

## Logo / mark

Four streams curve in from the left and **converge into a single node**, which
emits one calm channel to the right — literally "many sources, one current."

- Implemented as `ConfluendoMark` in `web/apps/site/app/admin/confluendo-brand.tsx`.
- The converging line and node use `currentColor`, so the mark inherits the
  surrounding text color and reads correctly on both light and dark surfaces.
- Two variants:
  - `accent` (default): two soft + two accent-blue streams. Use in mastheads and
    auth cards.
  - `spectrum`: coral / amber / teal / indigo streams. Use for hero moments
    (e.g. the sign-in brand panel) and the favicon.
- Favicon: `web/apps/site/app/admin/icon.svg` (scoped to `/admin/*` only).

## Color tokens

Defined as CSS custom properties in `web/apps/site/app/globals.css` and applied
only to platform surfaces (`.admin-sign-in-page`, `.admin-auth-page`,
`.provider-dashboard`).

| Token | Hex | Role |
| --- | --- | --- |
| `--cfl-ink` | `#0F1B2D` | Primary text / dark backgrounds |
| `--cfl-surface` | `#16263C` | Elevated dark surface |
| `--cfl-accent` | `#3B6EA5` | Primary accent: CTAs, links, focus, kickers |
| `--cfl-accent-soft` | `#6FA8C7` | Soft accent: dark-surface accents, badges, dots |
| `--cfl-paper` | `#F5F6F7` | Light page background |
| `--cfl-mist` | `#E8EAED` | Light divider / subtle fill |
| `--cfl-muted` | `#5B6B7D` | Secondary text |
| `--cfl-line` | `#DFE3E8` | Borders |
| `--cfl-stream-teal` | `#1FB6A6` | "Operational" status accent |

Spectrum streams (logo / hero / favicon only): `#FF6B5C` `#FFB03A` `#1FB6A6`
`#5B6BF0`.

## Type

| Role | Family | Loaded via |
| --- | --- | --- |
| Display / body | **Schibsted Grotesk** | `next/font/google` → `--font-confluendo` → `--cfl-font` |
| Mono / labels / codes | **IBM Plex Mono** | `next/font/google` → `--font-confluendo-mono` → `--cfl-font-mono` |

Fonts are attached on the root `<html>` and consumed only by platform-surface
CSS; the Vamo consumer pages keep the system stack.

## Scope rule (platform vs consumer)

- **Confluendo (platform):** `/admin/*` auth, ingestion, and provider surfaces;
  the operator OTP email (`docs/AUTH_EMAIL_TEMPLATE_BODY.html`); the `/admin`
  favicon. All carry the Confluendo mark, wordmark, palette, and type.
- **Vamo (consumer / project):** the public `/` landing, the `/j/[token]` invite
  pages, the consumer `send-auth-email` edge function, and the `vamo` project
  key. These remain Vamo-branded and are out of scope for the platform rebrand.
