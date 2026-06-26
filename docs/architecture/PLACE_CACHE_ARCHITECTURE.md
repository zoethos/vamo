# Place Cache Architecture

Status: strategic design, 2026-06-26.

This document is the companion to the cache architecture diagram. It defines how
Vamo resolves places, enriches them safely, and promotes durable cache data into
staging and production without mixing live-provider payloads, user observations,
or crawler noise into the shared knowledge layer.

![Vamo place cache architecture](assets/place-cache-architecture.png)

## Purpose

The place cache is a product asset, not just a performance optimization. It lets
Vamo:

- resolve free-text trip destinations and POIs quickly;
- avoid repeated paid/live provider calls for facts we can legally own;
- provide create-trip backgrounds, destination visuals, POI cards, map pins, and
  offline packs from one durable knowledge layer;
- preserve source attribution and license controls at the row level;
- keep user observations and global cache promotion structurally separate.

## Core Principle

Identity and content are separate planes.

- **Plane A: Live identity.** Provider APIs can resolve "what place is this" and
  return an opaque provider id plus coordinates. Live payloads are TTL-bound and
  cannot become durable content unless the provider policy explicitly allows it.
- **Plane B: Durable knowledge.** Open, attributed, or otherwise cacheable facts
  land in Vamo-owned canonical tables and visual cache rows. This is what app
  surfaces read from.

The link between the planes is a provider/source id. The provider id is a pointer,
not a copied provider payload.

## Runtime Resolve Path

1. The user enters a trip name, destination, POI, or natural-language place input.
2. `place-resolve` normalizes the query and checks cached aliases/canonicals.
3. On a cache hit, the app reads Plane B directly.
4. On a cache miss, live identity providers may return an opaque place id and
   coordinates.
5. The observation write and any enrichment/promotion work is asynchronous. Trip
   creation must not wait for cache writes.

## Durable Cache Plane

The durable layer is made of:

- `location_observations`: user-scoped evidence. This may carry `user_id`; it is
  not the global cache.
- promotion engine: projects trusted-source matches or cross-user corroborated
  observations into shared rows.
- canonical tables: `locations_core` / `location_canonicals`,
  `location_source_ids` / source refs, `location_aliases`, and
  `location_visual_cache`.
- provider policy guard: source-level controls such as `can_store_content`,
  `can_store_photos`, `max_retention_days`, and `requires_attribution`.
- offline projection: app-local read model that never carries Google/live-only
  payloads.

Promotion must physically exclude user identifiers from global tables. The shared
cache receives projected facts only: source, source id or URL, attribution, license
class, confidence, timestamps, and cache policy.

## Ingestion And Backfill Plane

For large-scale enrichment, Vamo uses a separate ingestion plane:

```text
dedicated ingestion worker
  -> ingestion Supabase project
  -> validation and policy gates
  -> Vamo staging
  -> Vamo production
```

The ingestion project is quarantine. It stores source observations, extracted
facts, rejected facts, and promotion batches. Staging and production receive only
validated normalized rows through idempotent promotion jobs.

Priority order:

1. Bulk/open datasets: FSQ OS Places, GeoNames, Wikidata dumps.
2. Structured public sources: Wikidata, Wikipedia, Wikimedia Commons.
3. OSM/Nominatim within policy limits, with no public-Nominatim bulk geocoding.
4. Official websites discovered from trusted fields such as Wikidata `P856`.
5. Live proprietary APIs only for identity or live-only fallback unless policy
   explicitly allows durable content.

## VPN And Egress Rule

Stable egress is allowed. Evasion is not.

Allowed:

- a dedicated PC or cloud VM;
- a stable VPN or dedicated IP;
- fixed egress region for QA and allow-listing;
- real Vamo user-agent, source-specific rate limits, backoff, and audit logs.

Not allowed:

- rotating VPN/proxy pools;
- residential proxy farms;
- CAPTCHA bypass;
- fingerprint spoofing;
- retrying through new IPs after a source throttles or blocks us.

The reason is architectural as much as legal: the cache must have clean provenance.
If a row reaches production, we should be able to explain how it was obtained,
why it can be stored, how it should be attributed, and how to roll it back.

## Promotion Rules

- Promote to staging first.
- Promote to production only after validation succeeds.
- Make every promotion idempotent by `(provider, source_id, source_hash)`.
- Never overwrite higher-confidence user-confirmed or trusted-source data without
  a recorded reason.
- Report added rows, updated rows, skipped rows, rejected rows, attribution
  changes, and collision warnings for every batch.
- Keep rollback handles per batch.

## App Consumers

The durable knowledge cache feeds:

- create-trip destination backgrounds;
- destination visual fallback;
- POI cards and details;
- trip map pins;
- offline essentials and future offline place projections.

App consumers should read durable cache projections. They should not know whether
a row was originally observed by a user, seeded from an open dataset, enriched
from Wikidata, or promoted through ingestion.

## Related Docs

- [Place Enrichment](../design/PLACE_ENRICHMENT.md)
- [Ingestion Control Architecture](INGESTION_CONTROL_ARCHITECTURE.md)
- [Provider Control Plane](PROVIDER_CONTROL_PLANE.md)
- [Provider Resilience](../design/PROVIDER_RESILIENCE.md)
