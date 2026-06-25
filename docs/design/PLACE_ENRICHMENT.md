# Place Enrichment — strategic architecture

**Status:** DESIGN. Scope = how Vamo turns a resolved place into rich, durable,
license-clean place data without violating any provider's terms.
**Relates to:** the place-intelligence cache (`supabase/migrations/20260625155733_place_intelligence_cache.sql`,
`place-resolve`), the deferred literal-spec follow-up, and Feature B (offline packs, which *consumes* this layer).

---

## 0. The one principle

Resolving **identity** ("what place is this") and acquiring **content** ("its name,
hours, photo, address") are two different operations with two different licenses.
**Separate them by license class — not by concealment.**

This is the load-bearing decision. Done this way, the architecture is something we
run in the open, attribute, and could show a provider's lawyer without flinching.
It is also simply better engineering: the content layer becomes a license-clean
asset Vamo *owns*, instead of a rented dependency we must re-pay on every read.

> Non-goal, explicitly: this design does **not** include proxy/IP rotation to hide
> a link between API use and enrichment, or "decoupled services so the provider
> can't detect the pattern." That is contract circumvention + detection evasion —
> it carries account-termination and legal exposure, and it contradicts the
> `live_only` guard already enforced in the migration. If a source's terms forbid
> an enrichment, the answer is a differently-licensed source, never a disguise.
> The license-class architecture below captures essentially all of the value
> (own the place layer, cut live-API cost, work offline) without that risk.
>
> A VPN can still be useful for stable network operations: a dedicated IP, a fixed
> egress region, and easier allow-listing from the ingestion host. What is excluded
> is rotating VPN/proxy use meant to bypass rate limits, blocks, country rules, or
> provider detection.

---

## 1. Two planes, joined by an opaque key

### Plane A — Identity (live, ephemeral, keyed)
Live provider APIs (Google Places, Foursquare live) answer only *"which place is
this"* and return an **opaque `place_id` + coordinates**. Nothing else is persisted
beyond the provider's retention window.

- The `place_id` (e.g. `ChIJN1t_tDeuEmsRUsoyG83frY4`) is an internal provider code.
  It does **not** appear anywhere on the open web and is useless on its own — so
  keeping it long-term as a *pointer/foreign key* is permitted and useful.
- Enforced today by `location_provider_policies` rows where
  `dataset_kind = 'live_api'`: `can_store_place_id = true`,
  `can_store_content = false`, `max_retention_days` set; and
  `location_visual_cache.cache_policy = 'live_only'` for Google.

### Plane B — Knowledge (owned, durable, license-clean)
The cache Vamo keeps indefinitely, built from openly-licensed and genuinely public
sources. This is where value compounds and what the app reads from.

- Seeded by `open_seed` providers — FSQ OS Places (Apache-2.0), GeoNames (CC BY 4.0),
  Wikidata (CC0) — plus enrichment (below).
- Lands in `location_canonicals`* (`has_details`, `attribution`, `confidence`,
  `promotion_state`), `location_visual_cache` (`cacheable`/`ttl`), and aliases via
  `promote_location_aliases`.

### The join
`location_source_refs`* / `source_place_id` is the pointer linking a Plane-A
identity to a Plane-B canonical. It is a key, not content — durable by design.

> \* Naming: today these are `location_canonicals` and `location_source_refs`. The
> deferred literal-spec slice renames them to `locations_core` / `location_source_ids`
> and adds PostGIS `geom`/GiST + pg_trgm. This doc uses the target intent; treat the
> current names as aliases until that slice lands.

---

## 2. Provenance — the clean chain

Enrichment keys off the **name the user typed** (`location_observations.query_norm`)
plus coordinates — never a provider-returned name. The chain is therefore:

```
user typed "Hotel Miramare Gaeta"
  → live API resolved coordinates + opaque place_id   (Plane A, ephemeral)
  → we look "Hotel Miramare Gaeta" up on open/licensed sources  (Plane B, durable)
```

This provenance is clean because it is *true*, not because it is hidden. The DB
guard (`can_store_content = false` for `live_api`) makes it structurally impossible
to write a live-API payload into the knowledge plane.

---

## 3. The enrichment pipeline (`place-enrich`)

A worker (Edge Function or scheduled job) takes a canonical `{name, lat/lng, country}`
and fills `has_details` + visuals from license-clean sources **in license-priority
order**. It writes `attribution` per row and respects each source's policy.

| Order | Source | License | Yields | Cache policy |
|---|---|---|---|---|
| 1 | **Wikidata / Wikipedia** | CC0 / CC BY-SA | description, official-site URL, image, ids | `cacheable` + attribution |
| 2 | **OSM / Nominatim** | ODbL | address, category, tags | `cacheable`, attribution, **no bulk**, honor usage policy |
| 3 | **Official site** (the place's own) | public | hours, contact, photos | modest `ttl`, store URL + attribution, honor robots.txt |
| — | FSQ OS bulk dataset | Apache-2.0 | categories, chains | seeded offline |

**Build order:** start with **Wikidata/Wikipedia** (structured, image + official-site
in one hop, lowest legal surface) → **OSM** → **official-site** last.

Each enrichment fetch:
- writes `location_canonicals.has_details = true` and `location_visual_cache`
  (`visual_kind` `provider_photo`/`stored_asset`, `cache_policy` `cacheable`/`ttl`);
- never writes Google/live-API content into Plane B (guard-enforced);
- records source + attribution; sets/refreshes `expires_at` per provider TTL.

---

## 4. Ingestion and incremental backfill plane

For large-scale enrichment, Vamo should not run ad hoc scraping directly against
staging or production. Use a separate ingestion plane that can be audited, throttled,
replayed, and discarded without polluting user-facing data.

### Terms

- **Backfill** = "riversare" historical or missing data into the cache.
- **Incremental sync** = keep the cache current after the initial backfill.
- **Promotion** = move validated normalized rows from ingestion into staging, then
  production.

### Runtime topology

```
dedicated ingestion PC
  -> ingestion Supabase project (quarantine)
  -> validation + policy gates
  -> Vamo staging
  -> Vamo production
```

The dedicated PC can run the crawler/worker continuously, but it writes only to the
ingestion Supabase project. Staging and production receive promoted rows through
idempotent jobs, never direct crawler writes.

### Network stance

- Allowed: a stable VPN or dedicated-IP egress for predictable networking,
  region-specific QA, and allow-listing. NordVPN is acceptable only in this mode;
  a cloud VM with static IP is also acceptable and often cleaner operationally.
- Not allowed: rotating VPN/proxy pools, residential proxies, CAPTCHA bypass,
  fingerprint spoofing, or retrying through new IPs after a provider throttles or
  blocks us.
- Every fetch uses a real Vamo `User-Agent`, source-specific rate limits, backoff,
  robots.txt where applicable, and an audit log.

The distinction is simple: **stable egress is infrastructure; rotation to avoid
provider controls is evasion.**

### Ingestion schema intent

The ingestion project should store:

- `source_observations`: URL/API/source id, fetch timestamp, status, content hash,
  provider policy id, and source attribution.
- `extracted_place_facts`: normalized candidate fields such as name, address,
  category, website, lat/lng, image URL, description, and confidence.
- `rejected_facts`: rows blocked by license, robots, low confidence, stale source,
  or collision.
- `promotion_batches`: immutable batch id, source filters, row counts, reviewer,
  staging result, production result, and rollback handle.

Raw HTML or raw API payloads are stored only when the provider policy explicitly
allows it. Otherwise the ingestion project stores hashes, metadata, extracted
facts, and enough audit evidence to explain the decision.

### Promotion rules

- Promote to staging first; production only receives rows that passed staging
  validation.
- Promotions are idempotent by `(provider, source_id, source_hash)` and never
  overwrite higher-confidence user-confirmed or trusted-source data without a
  recorded reason.
- Every promoted row carries `source`, `source_url`/`source_id`, `attribution`,
  `license_class`, `confidence`, `last_seen_at`, and `expires_at` when applicable.
- Promotion output includes added rows, updated rows, skipped rows, rejected rows,
  attribution changes, and collision warnings.
- Production receives normalized canonical data, not crawler noise.

### Source priority for backfill

1. Bulk/open datasets: FSQ OS Places, GeoNames, Wikidata dumps.
2. Structured public APIs with clear terms: Wikidata/Wikipedia/Commons.
3. OSM/Nominatim within policy limits; no bulk geocoding via public Nominatim.
4. Official websites discovered from trusted fields such as Wikidata `P856`.
5. Live proprietary APIs only for identity resolution or live-only fallback, never
   durable content unless the provider policy explicitly allows it.

---

## 5. Compliance guardrails (the inversion of "don't get caught")

Every concealment tactic flipped to its transparent equivalent:

- **Identify, don't hide.** Real Vamo `User-Agent` on every fetch (already required
  for OSM tiles by `docs/slices/TRIP_MAP_P0_PROMPT.md`). Stable dedicated egress is
  fine; IP rotation to conceal volume or identity is not.
- **Respect, don't evade.** Honor robots.txt + crawl-delay + per-provider rate
  limits and backoff (`docs/design/PROVIDER_RESILIENCE.md`).
- **Attribute, in the UI.** Surface the `attribution` we already carry
  (`location_*` tables + `DestinationVisual.attribution`).
- **Audit for transparency.** Keep the enrichment log because we would be
  comfortable showing it — not as deniability.
- **TTL the live plane.** Live payloads expire; only the open/owned plane is durable.

---

## 6. Provider policy registry

Extend `location_provider_policies` with the enrichment sources:

| provider | dataset_kind | can_seed_global | can_store_content | can_store_photos | requires_attribution | attribution |
|---|---|---|---|---|---|---|
| `wikidata` | open_seed | true | true | true | false (CC0) | Wikidata (CC0) |
| `wikipedia` | open_seed | true | true | true | true | Wikipedia (CC BY-SA 4.0) |
| `osm_nominatim` | open_seed | true | true | false | true | © OpenStreetMap contributors (ODbL) |
| `official_site` | derived | false | true | true | true | Place's official website |

(`fsq_os_places`, `geonames`, `wikidata`, `foursquare_places_api`,
`google_places_api`, `static_map`, `user_observation` already seeded.)

---

## 7. How it slots into the codebase

- **New:** `supabase/functions/place-enrich/`; the provider-policy seed rows above;
  a light enrichment queue/scheduler keyed off canonicals with `has_details = false`.
- **New, strategic:** a separate ingestion Supabase project plus a dedicated
  ingestion worker for backfill/promotion. This is a data-supply-chain component,
  not part of the mobile app runtime.
- **Reuses:** `place-resolve` (Plane A), `promote_location_aliases`,
  `location_visual_cache`, the `location_observations` flywheel.
- **Feeds, does not couple to, Feature B:** offline packs consume the Plane-B
  canonical projection locally (name/address/lat-lng/source-id), never Plane A.
- **Overlaps the deferred literal-spec slice** (chip): the PostGIS/geom/trigram
  rename and the `location_visual_cache` fallback chain are prerequisites; this doc
  is the reference that slice builds against.

---

## 8. Open questions

1. Enrichment cadence: on-demand at first resolve, or a background sweep over
   `has_details = false`? (Lean: on-demand for the active trip's places; sweep later.)
2. Official-site discovery: trust Wikidata's `official website (P856)` only, or also
   accept a verified domain from the resolver? (Lean: Wikidata P856 only at first.)
3. Photo rights from official sites: store URL + attribution and hot-link, or copy
   into storage? (Lean: URL + attribution only until per-site rights are checked.)
4. Refresh policy for `cacheable` open data (Wikidata/OSM change over time) — fixed
   TTL vs. change-feed. (Lean: long TTL + manual invalidation for v1.)
5. Ingestion host: dedicated PC with stable VPN/dedicated IP vs. cloud VM with static
   egress. (Lean: whichever gives us stable logs, uptime, and simple allow-listing.)
6. Promotion cadence: manual batch review first, then automatic low-risk promotions
   once the reject/collision reports are trustworthy.
