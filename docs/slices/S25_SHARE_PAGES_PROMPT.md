# S25 — Share pages (view-before-install) (P1 / W2 growth)

**Branch:** `feature/share-pages` · **Est:** ~2.5 dev-days · **Depends:** domain (live: `vamo.world`), `web/apps/site` exists
**Spec:** `Vamo_Wave2_Spec.md` — "view-before-install share pages"; user story: *"As an
invitee without the app, I want the invite link to show me the trip before any store visit."*
**Why now:** **fully decoupled from the Google Play blocker** — web tier on the live
domain, ships independently, growth engine. **Implement before S23** (S23 stores
theme on trip; S25 reads it via preview RPC).
**Out of scope:** public social "recap" pages; editing from web; auth/login on web;
exposing financial data; auto-redirect on page load; member names/avatars on preview
(deferred — see §1).

> Today `web/apps/site/app/j/[token]/page.tsx` **auto-redirects** via meta refresh
> and `JoinRedirect` (`window.location.replace(appUrl)`). That fights
> view-before-install and hurts unfurls. S25 **renders the preview first** with
> explicit **Open in app / Get the app** CTAs; app-link navigation is **CTA-driven
> only**, not on initial load.

## 0. Sequencing (read before coding)

1. **Fix main CI golden failure + merge #21** before starting S25.
2. **S25** (this slice) — web-only, ungated.
3. **S23** after S25 (theme resolver writes `trips.theme` at creation).
4. **S22 held** until device + cron dry-run pass.

## 1. Privacy model (non-negotiable)

- Page renders **only for a valid invite token** via **`get_trip_preview(p_token)`**
  (`security definer`, granted to **anon**). **No direct public table reads.**
- **Preview-safe fields only:**
  - Trip name, destination, date range
  - **Member count only** (e.g. "4 Vamigos going") — **not** first names, avatars,
    or roster (deferred; founder can reopen later)
  - Themed hero + watermark
  - **Theme pack** embedded in RPC response (`theme` jsonb from `trips.theme`, or
    brand default tokens) — **do not** anon-read `destination_themes`
- **Never:** expenses, balances, amounts, emails, member identities, notes.

### Invite invalid states (match current schema — do not invent)

Current `invites` columns: `token`, `expires_at`, `max_uses`, `uses`. There is
**no `revoked_at`** today. RPC + copy must use only:

| State | Condition | UX |
|-------|-----------|-----|
| **Invalid** | No row for token | Graceful "invite not available" |
| **Expired** | `expires_at < now()` | Same |
| **Exhausted** | `uses >= max_uses` | Same |

Do **not** document or implement "revoked" unless a follow-up migration adds
`revoked_at` with an explicit slice. Wording: "invite not available" covers all
three.

## 2. The page (SSR for unfurl — preview first, no auto-redirect)

**Remove** on initial load:

- `generateMetadata` `refresh: 0;url=app.vamo://…`
- `JoinRedirect` automatic `window.location.replace` on mount

**Render instead:**

- SSR trip preview card (hero, name, destination, dates, member count, watermark)
- **Primary CTA:** Open in app (sets `window.location` / intent **on click only**)
- **Secondary CTA:** Get the app (store / coming-soon)
- Preserve `token` + `ch` query param on CTAs (S26 `InviteChannel`)

**Open Graph / Twitter:** per-trip meta from preview RPC; dynamic OG image
(`opengraph-image.tsx` / `ImageResponse`) using **theme tokens from RPC** (not a
separate theme fetch).

Until S23 lands, RPC returns **brand default theme tokens** when `trips.theme` is
null. After S23, RPC projects stored `trips.theme` unchanged.

## 3. Caching / SEO (token URLs are not marketing pages)

- **`/j/[token]` must be dynamic SSR** — no static generation, no ISR cache of
  token responses.
- Next.js: `export const dynamic = 'force-dynamic'` (or equivalent); set
  `Cache-Control: private, no-store` on preview responses.
- **`robots`: `noindex, nofollow`** on token pages (default — not negotiable for
  S25).
- **No token in canonical URL** — canonical should omit or point to generic join
  landing, not embed the secret token.
- Invalid-token page: same cache/noindex posture; no trip data in HTML.

## 4. Files

- `web/apps/site/app/j/[token]/page.tsx` — SSR preview + OG meta; **no auto-redirect**
- `web/apps/site/app/j/[token]/opengraph-image.tsx` (new) — dynamic OG from RPC theme
- `web/apps/site/app/j/[token]/join-redirect.tsx` — **delete or repurpose** as
  click-handler only (no `useEffect` redirect on mount)
- Supabase migration: `get_trip_preview(p_token)` — preview-safe projection +
  **`theme` jsonb** (from `trips.theme` or default pack); anon execute; **revoke
  any broad anon table read**
- Reuse `web/apps/site/public/brand/*`

### `get_trip_preview` contract (sketch)

Returns `null` when invalid/expired/exhausted. On success, jsonb fields only:

```json
{
  "trip_name": "...",
  "destination": "...",
  "start_date": "...",
  "end_date": "...",
  "member_count": 4,
  "theme": { /* SnapshotThemePack-compatible tokens or default */ }
}
```

No member roster. No financial fields. Theme resolved server-side inside RPC.

## 5. Resilience

- Supabase failure or null RPC → graceful "invite not available" (never 500 with
  internals).
- Publishable Supabase key only in web bundle.
- `PROVIDER_RESILIENCE` posture on preview fetch.

## 6. Verification

- **Social unfurl:** link-preview tester shows trip title + OG image (not generic
  redirect page).
- **Logged-out browser:** valid token → full preview HTML visible **before** any
  navigation; **no auto app-scheme redirect** on load.
- **Invalid / expired / exhausted:** graceful page; no trip data; no 500.
- **CTA click:** App Links → installed app with token + `ch`; else store/coming-soon.
- **Privacy assert:** HTML/JSON payload has member_count only — no names, amounts,
  emails.
- **Cache headers:** `no-store` on `/j/[token]`; `noindex` present.
- `npm run build` green; Vercel deploy on live domain; Lighthouse sane on mobile.
- `get_trip_preview` unit/smoke: valid token → preview fields + theme; invalid →
  null; exhausted/expired covered.

## 7. Reviewer checklist

- [ ] Preview gated on `get_trip_preview`; **no public theme/invite table read**
- [ ] RPC includes **theme pack** (trip theme or default); not separate anon theme fetch
- [ ] **No auto-redirect** on page load (meta refresh + JoinRedirect removed)
- [ ] CTA-driven app open only; token + `ch` preserved
- [ ] **Member count only** — no names/avatars on preview
- [ ] Invalid/expired/**exhausted** only (no invented "revoked" unless migrated)
- [ ] **Zero financial/PII** in page or payload
- [ ] SSR + OG/Twitter + dynamic OG image (unfurl verified)
- [ ] Watermark present; themed hero from RPC theme
- [ ] **`noindex` + no-store**; no token in canonical; force-dynamic
- [ ] `npm run build` green; live domain verified

## Notes

- **S23 after S25:** creation-time `resolve-theme` fills `trips.theme`; preview
  automatically picks it up via RPC — no S25 code change needed post-S23.
- Public social recap pages remain a **later** slice.
