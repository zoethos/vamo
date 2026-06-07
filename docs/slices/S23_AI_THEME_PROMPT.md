# S23 — AI theme resolver (W2·R10)

**Branch:** `feature/ai-theme` · **Est:** ~2 dev-days · **Depends:** none (parallel-safe; **implement after S25** — see `README.md` sequencing)
**Binding spec:** `docs/AI_THEMING_SPEC.md` — **read it first; it governs.** This
prompt is the slice framing, not a replacement for that spec.
**Spec row (R10):** "AI theme resolver — cache hit serves without LLM; validation
gates enforced; fallback intact."
**Out of scope:** theme **monetization** (selling themes is later — B2B+branding);
per-element manual theming UI; animation/illustration generation; resolving theme
at share/preview time (that reads `trips.theme` only).

> Resolve a trip's visual theme (palette + accents within the design system) from
> its **destination field only**, **cheaply and safely**: a global destination
> cache so repeat places never hit the LLM, **validation gates** so raw model
> output can't drive the UI unchecked, and a **default fallback** so theming can
> never break the app.

## 0. Sequencing (read before coding)

1. **Main CI green + merge #21** (golden fix) before new slice work.
2. **S25 first** (share pages — web-only, growth, no Play gate).
3. **S23 next** (this slice). S25 preview/OG consumes **`trips.theme`** via
   `get_trip_preview` — no anon read of theme tables.
4. **S22 held** until device + cron dry-run pass.

## 1. Hard rules (the three R10 gates + spec ladder)

1. **Cache-first (cost control).** Global cache in **`destination_themes`**
   keyed by **`canonical_key`** (e.g. `rome-it`), with **`destination_theme_aliases`**
   for normalized raw inputs. **Cache hit serves with NO LLM call.**
2. **Validation gates.** Model returns structured **`SnapshotThemePack`** tokens
   only; every field validated per `AI_THEMING_SPEC.md` § Validate. **Invalid →
   reject → fallback.** Raw model output never reaches the UI or cache.
3. **Fallback intact.** LLM unavailable / over-quota / timeout / invalid output →
   brand default pack (Slice 12 `KeywordThemeResolver` / `defaultPack`). Silent;
   app never blocks.

**Resolution ladder (binding — do not invent alternatives):**

| Step | When | Action |
|------|------|--------|
| 1 | Trip already has `trips.theme` jsonb | Render stored pack. Offline-first. |
| 2 | **Trip creation only** (never share time) | Call `resolve-theme` Edge Function with **`destination` field only**; on success **persist pack on `trips.theme`**. |
| 3 | Function unavailable / empty destination | Local keyword resolver → default pack. |

**Privacy:** Only **`trips.destination`** goes to the resolver. **Trip names never
leave the device** for theming. No PII in cache, logs, or analytics.

## 2. Architecture (use spec table names — not `theme_cache`)

- **Server-side only.** LLM called from Edge Function `resolve-theme`
  (service-role). Never the client.
- **Tables** (migration adds if missing):
  - `destination_themes` — `canonical_key` PK, `pack` jsonb, `display_name`,
    `model`, `schema_version`, `review_status`, `created_at`
  - `destination_theme_aliases` — `alias` PK → `canonical_key` FK
  - `trips.theme` jsonb — stored pack on the trip row after creation-time resolve
- **RLS:** both theme tables **read-only for `authenticated`** only (global,
  non-personal content). **Writes service-role only** (Edge Function). **No anon
  / public read** — share pages get theme via `get_trip_preview` (S25), not direct
  table access.
- **Edge Function flow** (`resolve-theme`, input `{ destination: string }`):
  1. Normalize (lowercase, trim, diacritics/punctuation strip).
  2. Alias lookup → theme lookup → return on hit (**no LLM**).
  3. Miss → one cheap LLM call → validate → upsert theme + alias → return pack.
  4. Fail → return fallback signal (**do not cache failures**).
- **Client:** invoke at **create-trip** (after trip row exists), write returned
  pack to `trips.theme`. Do **not** call on every navigation or at share time.

## 3. Provider + resilience

- Add LLM provider to **`docs/DEPENDENCIES.md`** (tier, cost-watch, secret in
  Supabase — never client bundle).
- `PROVIDER_RESILIENCE.md`: 429/5xx/timeout → bounded wait → fallback; log
  `provider_throttled`.
- Edge fn deno hygiene (`SECURITY_PATCHING.md` §2.1): `deno.json`, frozen
  `deno.lock`, `deno check`, no raw imports.

## 4. Verification

`tool/rls_smoke.dart` / unit:

- **cache hit → no LLM call** (model path not invoked when cached).
- **cache miss → LLM once → validated → cached**; second request same destination
  = hit.
- **invalid output → fallback**, not cached.
- **LLM unavailable/timeout → fallback**, app unaffected.
- **no PII** in model payload (destination/coarse context only).
- Validation unit tests: malformed / low-contrast / unsafe sets rejected.
- **anon cannot SELECT** `destination_themes` / `destination_theme_aliases`.
- **`trips.theme`** writable only via expected path (creation RPC or guarded
  update — no client forgery).

`melos run ci` green + smoke PASS. Edge fn **deploy + invoke-once** verified.

## 5. Reviewer checklist

- [ ] Reads/obeys `docs/AI_THEMING_SPEC.md` (table names, ladder, privacy)
- [ ] Uses **`destination_themes` + `destination_theme_aliases`**, not `theme_cache`
- [ ] Resolve at **trip creation**, store on **`trips.theme`**; never at share time
- [ ] Cache hit = **no** LLM call (proven)
- [ ] Validation gates enforced; invalid → fallback (not cached)
- [ ] Theme tables **authenticated read only**; no anon/public table read
- [ ] Share/preview theme only via **`get_trip_preview`** (S25), not broadened RLS
- [ ] LLM server-side only; no PII to model/cache/analytics
- [ ] Edge fn: frozen `deno.lock` + `deno check`; deploy + invoke-once

## Notes

- **S25 tie-in:** preview/OG read **`theme` from `get_trip_preview`**, which
  projects `trips.theme` or default — S25 does not call `resolve-theme`.
- **Monetization deferred:** `review_status = overridden` is the later B2B hook.
- Reconcile with Slice 12 `KeywordThemeResolver` / snapshot packs — extend, don't
  duplicate.
