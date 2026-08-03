# Place-data rights enforcement - programme (rev 5)

**For:** Codex / Cursor (full repo access).
**Parent plan:** `docs/architecture/Vamo_Data_Acquisition_Strategy.docx` (sections 5-10, load-bearing rules section 9).

> **Rev 5 supersedes rev 4 in full.** D1-D4 and the promotion threshold are settled
> decisions, not implementation choices. Do not work from rev 1-4.

## Programme

| PR | Scope | Status |
| --- | --- | --- |
| **PDA-0** | Stop the live title-storage violation and remediate stored titles | **Ready - ship first, standalone** |
| **PDA-1** | Database-test foundation, promotion function, and provider-cache retention | **Ready - test foundation is part of the slice** |
| **PDA-2** | Observation table split and write-time enforcement | **Ready after PDA-0 and PDA-1 promotion checks** |
| **PDA-3** | Metering | **Ready after PDA-1** |

## Settled decisions

### D1 - table split

`location_observations` becomes purely Vamo-owned. A new optional one-to-one child,
`location_observation_provider_facts`, holds provider-derived facts:

| Column | Rule |
| --- | --- |
| `observation_id` | Primary key and FK to `location_observations(id) on delete cascade` |
| `provider` | Not null FK to `location_provider_policies(provider)` |
| `provider_place_id` | Allowed only where `can_store_place_id` is true |
| provider content | Allowed only where `can_store_content` is true |
| `attribution` | Lives and dies with the provider facts |
| `fetched_at`, `expires_at` | Expiry derived from the authoritative provider policy at write time |

Redaction is deletion of the child row; the Vamo user event survives. Parent `origin`
describes the event, not provider data: `legacy_unknown | user_entered | device_fix`.
`provider_resolved` is removed. Request-input coordinates and Vamo's `poi` feature-type
literal remain on the parent because they are not provider payload.

### D1a - promotion enforcement is by role

Create dedicated `NOLOGIN` role `vamo_place_promotion` idempotently. It receives only:

- `select` on `location_observations` and `location_canonicals`;
- `select, insert, update` on `location_aliases`;
- no grant on `location_observation_provider_facts`.

`promote_location_aliases(integer, integer)` is owned by `vamo_place_promotion`, not
the migration owner. Test both the function source and the actual negative privilege
boundary: `set role vamo_place_promotion; select 1 from
location_observation_provider_facts;` must fail with insufficient privilege.

### D2 - one external product, separate internal service

`poi-discovery` and `destination-visual` both call Foursquare `/places/search` with the
same key; the visual flow merely requests the `photos` field. It does not call the
separate `/places/{id}/photos` endpoint.

- Add `provider_config` row `destination_visual` / `foursquare` so visual requests do
  not consume POI-discovery quota or blur product metrics.
- Add nullable `rights_policy_provider` FK to `location_provider_policies(provider)`.
  Set it to `foursquare_places_api` for both place services.
- `provider_config` remains the operational authority for non-place services such as
  OpenAI and OpenRouteService. Where `rights_policy_provider` is set, the referenced
  policy governs rights and retention.

### D3 - meter external attempts, not user gestures

For `destination-visual`, create server-side key
`destination-visual:attempt:<uuid>` once an outbound Foursquare request will happen.
A user retry is a further external attempt and receives a new key. Release the
reservation only before a provider call starts; after the HTTP request starts it remains
counted even when the outcome is unknown. `fresh_calls` is deliberately a conservative
measure of paid provider attempts. No Flutter request-ID change is needed.

### D4 - database policy is authoritative

`location_provider_policies` is the sole authority for place-data rights and retention.
Edge Functions read it at write time, cached only for the current invocation. A database
trigger independently sanitizes or rejects prohibited provider facts.

Remove the hardcoded TypeScript rights object. TypeScript may keep provider identifiers
and the operational-service-to-rights-policy mapping, but must not retain parallel policy
values. `provider_config` remains operational configuration for all services.

### Promotion threshold

Promotion requires **at least three distinct users and two distinct UTC days**. This is
enforced by `promote_location_aliases`, not merely by a caller convention. The
two-argument signature may remain for explicitness, but it must reject a user threshold
below three or a day threshold below two. Do not leave a callable two-user promotion path.
If two-user analysis is ever needed, it belongs in a separate owner-only diagnostic
function, never in promotion.

### Rule 4

> Provider payloads live only in expiry-bound provider stores and never in the canonical
> graph or promotion path.

## PDA-0 - containment hotfix and remediation

**Branch:** `fix/destination-visual-title-storage`.

`destination-visual` must pass `resolvedDisplayName: null` to
`recordLocationObservation`. It must preserve the user query, request coordinates,
provider place ID, attribution, observation kind, selected state, and response shape.

Migration `20260803120000_redact_foursquare_observation_titles.sql` clears only existing
`resolved_display_name` values where `provider = 'foursquare_places_api'`, and reports
the row count as a migration notice. The predicate is safe: `destination-visual` is the
sole repository writer of that provider value and sourced its title from Foursquare.

The source assertion is an explicit temporary guard: `Deno.serve` runs at module scope
and `scheduleObservation` is not exported. PDA-2 replaces this with structural writer
and trigger enforcement. The migration needs a staging and production verification that
the scoped values were cleared and `user_observation` rows were untouched.

## PDA-1 - testable promotion and provider-cache retention

**Branch:** `feat/place-promotion-hardening`.

### Database-test foundation

PDA-1 adds the smallest supported database-test home:

- `supabase/tests/database/place_data_rights.test.sql`, using pgTAP;
- CI starts a disposable local Supabase stack, applies the migration history, and runs
  `supabase test db` in a dedicated database-test job;
- tests run only against that disposable local stack, never Staging or Production.

This foundation is part of PDA-1 because its promotion, overload, role, and retention
claims are database behaviour. Keep the existing Deno Edge-Function tests; do not add a
repo-wide formatting pass.

### Promotion function

- Explicitly drop `public.promote_location_aliases(integer)` before creating the new
  two-argument function; `create or replace` would otherwise retain the unsafe overload.
- Create `security definer` function with fixed promotion requirements: at least three
  distinct users and two distinct UTC dates. Do not expose lower thresholds to callers.
- `trusted_source_match` may raise confidence but never bypasses corroboration.
- Derive country and feature type from the canonical record; never aggregate
  provider-derived observation columns. Attribution is the Vamo constant
  `Vamo user-confirmed observations`.
- Reconcile aliases already promoted through the old bypass: demote insufficiently
  corroborated `user_observation` aliases to `pending_review`, clear `promoted_at`, and
  report the count. Do not delete them.

### Retention

`purge_expired_place_intelligence(p_dry_run boolean default false)` is a security-definer
function with one mutation/counting code path. It is the enforcement point for
`location_provider_policies.max_retention_days`.

| Store | Rule |
| --- | --- |
| `location_resolution_cache` | Delete after `expires_at` |
| visual `live_only` | Delete unconditionally and report separately; persistence is itself a defect |
| visual `ttl` | Delete after non-null `expires_at` |
| visual `cacheable` | Where policy has finite retention, delete after `fetched_at + max_retention_days`; otherwise retain |
| `location_source_refs` | Delete after `expires_at`, or after policy-derived retention where expiry is null |
| `location_observations` | Out of scope until PDA-2 |

Create separate `place-data-retention` function and scheduled-job record with its own
heartbeat. Do not hide a compliance purge inside trip lifecycle work.

### Required database tests

1. Old one-argument overload absent; two-argument function present.
2. Three users on one day do not promote; two users over two days do not promote; three
   users over two days promote.
3. One trusted observation does not promote.
4. Promotion function does not read provider fields, and its owner cannot select the
   provider-facts child table once PDA-2 exists.
5. Legacy bypass promotion demotes to `pending_review`.
6. `live_only` visual rows are deleted regardless of expiry; finite-policy `cacheable`
   rows with null expiry expire by `fetched_at`; unlimited-policy cacheable rows survive.
7. Dry run changes no rows and returns the same counts as a subsequent real purge.

## PDA-2 - observation split and write-time enforcement

Implement D1 and D1a. Move provable provider facts to the child table before dropping
legacy parent columns. Backfill parent origins only when deterministic; otherwise use
`legacy_unknown`. New writes require an explicit parent origin.

Database and shared writer enforce the policy from D4. `metadata` receives a Vamo-owned
key allowlist in both layers; provider title, address, or photo URL cannot evade named
column rules. The parent retention rule is a separate Vamo product decision and must not
be invented here.

## PDA-3 - metering

`place-resolve` has no external provider call and is not metered. Meter
`destination-visual` through reservation, completion, and release using D3 semantics and
the `destination_visual` / `foursquare` operational service. Document a metric read for
paid API calls per active user per month.

## Out of scope

- Device GPS capture and any Flutter geolocation dependency.
- Changing canonical coordinates.
- Altering `provider_config` rights behaviour for non-place services.
