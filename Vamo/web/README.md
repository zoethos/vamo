# Vamo — web tier (TypeScript)

This subtree is the TypeScript side of the monorepo, managed by **npm workspaces +
Turborepo** — completely independent of the Dart/Melos side. It shares no source
code with the Flutter app; the contract between them is `../supabase/` (one schema,
one migration chain).

Nothing here builds yet — apps land with their waves:

| App | Arrives | Purpose |
|-----|---------|---------|
| `apps/share-pages` | Wave 2–3 | Public Next.js pages: view-before-install trip preview behind invite links, branded snapshot/recap share pages (SSR for link unfurls + SEO). Vercel. |
| `apps/operator-console` | post Wave-3 gate | B2B console for tour guides/operators: geo-anchored multi-language audio/media authoring, participant feedback. Extension of the consumer schema via operator entitlements — never a fork. |
| `packages/@vamo/*` | as needed | Shared TS types (generated from the Supabase schema), UI primitives. |

When the first app lands: `npm install` here, then `npx turbo run dev`.
See `../ARCHITECTURE.md` → "Repository growth path" and "Web strategy".
