# AI theme resolution with global destination cache (Wave 2)

Supersedes the keyword-only resolver from Slice 12. The four built-in packs
(`snapshot_themes.dart`) remain as the **offline fallback tier and the schema
definition** — the card always renders structured `SnapshotThemePack` tokens,
never free-form AI output.

## Principle

Generate once per *place on Earth*, serve forever from cache. 1M trips to Rome
= 1 LLM call + 999,999 table reads. The LLM is the cache-miss handler, not the
hot path.

## Resolution ladder (client)

1. Trip already has a stored theme (`trips.theme` jsonb) → render it. Offline-first.
2. At **trip creation** (never at share time): call `resolve-theme` Edge Function
   with the **destination field only** (see privacy note), store the returned
   pack on the trip row.
3. Function unavailable / destination empty → local `KeywordThemeResolver`
   (Slice 12 packs) → `defaultPack`.

## Privacy rule (important)

Only the `destination` field is sent to the resolver and only its normalized
form becomes a cache key. **Trip names never leave the device for theming** —
"Mario's stag do, Rome" must not become a shared cache row. Trip-name keyword
matching stays local-only fallback.

## Data model

```sql
create table destination_themes (
  canonical_key text primary key,        -- 'rome-it'
  pack          jsonb not null,          -- validated SnapshotThemePack tokens
  display_name  text not null,           -- 'Rome'
  model         text not null,           -- generator model id
  schema_version int not null default 1, -- bump to lazily regenerate all
  review_status text not null default 'auto' -- auto | reviewed | overridden
                check (review_status in ('auto','reviewed','overridden')),
  created_at    timestamptz not null default now()
);

create table destination_theme_aliases (
  alias         text primary key,        -- normalized raw input: 'roma italia'
  canonical_key text not null references destination_themes(canonical_key)
);
```

RLS: both tables **read-only for `authenticated`** (content is global,
non-personal), writes only via service role (the Edge Function). Aliases mean
"Roma", "Rome, Italy", "rome italia" all converge after their first miss.

## Edge Function `resolve-theme`

Input: `{ destination: string }`.

1. Normalize: lowercase, trim, strip diacritics + punctuation.
2. Alias lookup → theme lookup → return on hit.
3. Miss: one call to a small/cheap LLM. Prompt returns **JSON only**:
   canonical key + display name, 3-color gradient (dark, evocative of the
   place), stat panel colors, accent, member bubble colors, and the
   local-language "let's go" tagline (≤ 16 chars).
4. **Validate before caching** — reject and fall back to default on any failure:
   - JSON parses to the exact token schema (no extra fields).
   - All colors valid hex; gradient luminance below threshold (watermark is
     light-on-dark — contrast ≥ 4.5:1 against all gradient stops).
   - `statPrimary` vs `statBackground` contrast ≥ 4.5:1.
   - Tagline: length cap, single line, no URLs/digits.
5. Upsert theme + alias; return pack.

Provider note: S23 uses OpenAI from the Supabase Edge Function only, with
Structured Outputs / strict JSON schema for the `SnapshotThemePack` shape.
`OPENAI_API_KEY` lives as a Supabase secret and is never bundled into the app or
web client.

## Invariants

- Wordmark/watermark: same mark, same position, every theme, every tier. The
  schema has no field that can affect it.
- A failed generation is invisible to the user (default pack) — never an error.
- `schema_version` bump = lazy regeneration on next request per destination,
  not a batch job.
- `review_status` enables a later curation pass: hand-tuned packs for top
  destinations (`overridden`) win over generated ones and are never
  regenerated. This is also the B2B hook: operator-branded themes are
  `overridden` rows scoped to their trips (post Wave-3 gate).

## Cost envelope

Distinct real-world destinations are bounded (~10⁴–10⁵ at any plausible scale).
At small-model pricing this is single-digit dollars *cumulative*, amortized
over the product's life. Per-share cost: zero (pack stored on trip).

## Analytics

`snapshot_shared.theme_id` becomes `canonical_key` (or `default`/pack id for
fallback) — same closed-vocabulary property, now with global coverage.
`theme_resolved` event on cache miss (`canonical_key`, `cached: false`) gives
the cache hit-rate for free.
