# Vamo — web tier (TypeScript)

This subtree is the TypeScript side of the monorepo, managed by **npm workspaces +
Turborepo** — completely independent of the Dart/Melos side. It shares no source
code with the Flutter app; the contract between them is `../supabase/` (one schema,
one migration chain) and shared invite URL shapes (`InviteUrls` in `app_core`).

## Quick start

```bash
cd web
npm install
npx turbo run build    # all apps
npx turbo run dev      # local dev (site on :4373)
```

## Apps

| App | Status | Purpose |
|-----|--------|---------|
| `apps/site` | **Live (vamo.world)** | Landing, privacy, terms, `/j/[token]` view-before-install preview (S25), Android App Links file. Deploy on Vercel. |
| `apps/share-pages` | ~~Wave 2–3~~ | **Superseded by S25 in `apps/site`** — do not add a separate app for invite preview. |
| `apps/operator-console` | post Wave-3 gate | B2B operator console. |

## Vercel — `apps/site`

1. Create a Vercel project pointing at this repo.
2. Set **Root Directory** to `web/apps/site` (or deploy via monorepo with that path).
3. Framework preset: **Next.js** (`vercel.json` included).
4. Domain: attach **vamo.world** (and `www` redirect if desired).
5. Before Play release: update `public/.well-known/assetlinks.json` with real
   SHA-256 fingerprints (upload key + Play App Signing — see
   `.well-known/README.md`).
6. Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` (see
   `apps/site/.env.example`) so `/j/[token]` can call `get_trip_preview`.

Build command (from repo root via Turborepo): `cd web && npm install && npx turbo run build --filter=@vamo/site`.

See `../ARCHITECTURE.md` → "Repository growth path" and "Web strategy".
