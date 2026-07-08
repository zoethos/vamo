# IP-18.6 - Production Inbox Package Waves

Status: **IP-18.6.4 apply telemetry implemented** — read-only inbox polling,
control-plane mirror, and dashboard apply states (2026-07-07). IP-18.6.3
delivery CLI is live-proven. Consumer apply execution remains Vamo-owned.

## Purpose

IP-18.6 turns the proven IP-17 production-inbox pipe into a governed batch-wave
mechanism. Confluendo should be able to build data inside its own control,
source, cache, and package ledgers, then deliver validated packages to a
consumer inbox according to the consumer's contract.

The consumer defines what it can accept: schema, constraints, inbox/apply
contract, legal retention, and delivery credentials. Confluendo owns the
ingestion, source selection, normalization, telemetry, package assembly, and
decision to deliver a package inside the policy envelope until the package is
handed off to the consumer inbox.

For Vamo customer zero, this means production delivery still writes only to
Vamo production's `confluendo_inbox` schema. Vamo-owned apply remains separate.

## What IP-17 Proved

IP-17 proved a tiny live package can be delivered and applied:

- package `production-inbox:vamo-place-intelligence-staging:approval:13`
- Vamo apply result: `applied=2`, `skipped=0`, `rejected=0`
- checksums computed inside Vamo Postgres
- `confluendo_inbox_app` could write only inbox tables, not Vamo product tables
- failed package `approval:10` remains spent audit history and must not be retried

IP-18.6 scales that pipe from one manually approved package to bounded package
waves over staging-proven units.

## Non-Goals

- No direct writes to consumer product tables.
- No JavaScript authority for production package checksums.
- No retry of spent package ids.
- No aggregate write path bypassing the IP-17 production-inbox adapter.
- No autonomous production delivery until package-wave state, apply telemetry,
  and policy limits are implemented and proven.
- No widening of staging-canary wave caps. Staging volume is governed separately.

## Required Boundaries

### Confluendo-Owned Before Handoff

Confluendo owns:

- source ingestion and snapshot selection;
- candidate normalization and policy filtering;
- batch queue state and run reports;
- staging-canary evidence;
- package assembly;
- production package approval policy;
- package-wave ledger and telemetry;
- delivery decision inside approved bounds.

### Consumer-Owned At and After Handoff

The consumer owns:

- production inbox schema and login credentials;
- product-table apply function;
- product RLS and domain constraints;
- apply acceptance/rejection rules;
- product-table rollback or remediation;
- consumer-side legal/runtime constraints.

The inbox is the contract seam: Confluendo delivers packages; the consumer
applies them.

## State Model

IP-18.6 should introduce package-wave state without overloading staging wave
state:

```text
staging_canary_succeeded
  -> production_package_ready
  -> production_package_approved
  -> production_package_delivering
  -> production_package_delivered
  -> consumer_apply_pending
  -> consumer_applied | consumer_apply_failed | production_package_blocked
```

The exact persisted status names may be implemented as queue-item statuses,
package-wave statuses, or both. The important invariant is that package
delivery and consumer apply are different states.

## Eligibility

A unit is eligible for a production package wave only when all are true:

- queue item status is `staging_canary_succeeded`;
- target key is environment-neutral, for example `vamo-place-intelligence`;
- the package wave target environment is explicitly `production`;
- the staging evidence is explicitly from the consumer staging target, not
  inferred from target-key text;
- source/provider policy permits durable delivery;
- latest dry-run report has `wroteToTarget=false`;
- latest staging canary shipment succeeded for the same unit;
- no active blockers remain;
- no delete operations are present;
- package payload can be tied to deterministic canonical keys;
- shipment diff is compatible with the consumer package schema;
- the unit has not already been delivered in an active or applied package.

The policy must never infer production from target-key text.

## Package Wave Model

A package wave is a bounded group of eligible units assembled into one or more
IP-17-compatible packages.

Recommended initial Vamo wave:

- first production package wave: 1 unit;
- max rows: the approved policy cap, initially small;
- max package count: 1;
- explicit admin approval with fresh MFA and audit reason;
- confirmation-gated CLI execution;
- Vamo apply remains a separate Vamo-owned step.

Later package waves may widen by policy only after telemetry shows:

- package delivery success;
- consumer apply success or accepted no-op;
- no checksum mismatches;
- no schema-contract rejections;
- low blocker/drift rate;
- no unresolved failed packages for the same target.

## Package Assembly

Implementation must reuse the existing IP-17 package builder and adapter:

- `buildProductionInboxPackage(...)`
- `deliverPostgresProductionInboxPackage(...)`
- `production-inbox-policy.ts`
- `production-inbox-control.ts`
- `shipment-package.ts`

The package-wave layer chooses eligible units and bounds. It does not create a
second package format or a second target adapter.

Payload and package checksums remain computed in the consumer Postgres inbox,
not in JavaScript. The Confluendo package ledger stores returned checksum
evidence, package id, package key, approval id, delivery id, and apply status.

## Approval Policy

Production package-wave approval should mirror the IP-17/IP-16 bar:

- `ingestion_admin` / admin operator only;
- verified AAL2;
- fresh MFA step-up;
- non-empty audit reason;
- explicit target environment `production`;
- bounded `maxUnits`, `maxRows`, and `maxPackages`;
- no production handoff if consumer inbox prerequisites are missing;
- optimistic concurrency on package wave status;
- every approval writes audit and event rows.

Approval records the decision only. Delivery remains confirmation-gated.

## Execution Policy

Execution should be CLI/runbook first, then autonomous later:

- preview by default;
- execute requires `CONFIRM_CONFLUENDO_PRODUCTION_PACKAGE_WAVE=YES`;
- requires `INGESTION_CONTROL_DATABASE_URL`;
- requires consumer inbox DSN, for Vamo:
  `VAMO_PRODUCTION_INBOX_DATABASE_URL`;
- requires explicit `VAMO_PRODUCTION_INBOX_ENVIRONMENT=production`;
- run `releaseExpiredProductionPackageWaves` before selecting a deliverable wave;
- refuses staging sentinels or non-production proof;
- stop-on-first-failure for the first live wave;
- skip already delivered/applied packages on idempotent replay;
- record package delivery result and returned checksum evidence;
- never call the consumer apply function.

Consumer apply telemetry is read/recorded after the consumer applies the
package. Use `VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL` with the
`confluendo_inbox_telemetry` read-only role — never the writer DSN and never
product-table reads from Confluendo.

## Control Tables

Likely control-plane additions:

- `ingestion_batch_production_package_waves`
- `ingestion_batch_production_package_wave_items`

Minimum fields:

- `project_id`, `plan_id`, `wave_key`, `target_key`, `target_environment`;
- approval audit id, approval reason, approved by, approval expiry;
- status and timestamps;
- `max_units`, `max_rows`, `max_packages`;
- package ids, shipment ids, package checksum evidence;
- consumer apply status and evidence;
- blockers and corrective actions.

Grants should be narrow:

- runtime role can read package-wave state;
- approved route/function can insert/update package-wave state;
- no `DELETE`;
- no write grants to consumer product tables;
- no owner-level consumer DSN in browser or client code.

## Idempotency

Package ids must be stable and never reused across incompatible package content.
Recommended key shape:

```text
batch-production-inbox:{planKey}:wave:{approvalAuditId}:unit:{unitKey}
```

For multi-unit package waves, either:

- one package per unit for the early ramp, or
- one package per bounded wave with item keys scoped by unit.

The first implementation should prefer one package per unit or an explicitly
bounded single-package wave, whichever reuses IP-17 with less novelty.

Matching package id + matching package checksum is idempotent success. Matching
package id + different checksum is a hard block.

## Telemetry

Every wave should expose:

- package wave key;
- selected unit keys;
- dry-run execution evidence;
- staging canary shipment evidence;
- approval audit id;
- delivery execution audit id;
- package id and checksum;
- consumer inbox status;
- consumer apply status;
- blocker codes and corrective action recommendations.

Dashboard language must distinguish:

- "delivered to production inbox";
- "consumer apply pending";
- "consumer applied";
- "consumer apply failed";
- "package blocked before delivery".

The old ambiguity between "already delivered" and "failed apply" must not come
back.

## Autonomy Integration

IP-18.7 currently pauses production handoff with `waiting_for_ip18_6`. IP-18.6
should provide the missing state and policy hooks so autonomy can later:

1. detect `production_package_ready` units;
2. propose or request package-wave approval;
3. execute delivery only when the active autonomy policy explicitly allows it;
4. pause on consumer apply failures, checksum mismatches, or blocker thresholds.

Autonomy should not self-enable production delivery. A human-approved policy
must permit the transition, and production handoff should remain disabled until
IP-18.6 package waves plus apply telemetry are proven.

## Suggested Implementation Slices

### IP-18.6.0 - Design

This document and roadmap updates only.

### IP-18.6.1 - Policy and Schema (implemented)

- Package-wave control tables (`ingestion_batch_production_package_waves`,
  `ingestion_batch_production_package_wave_items`) and queue statuses added.
- Pure eligibility/approval policy with 15-minute approval freshness
  (`PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS`).
- Persistence/read model with idempotent wave approval and
  `latestProductionPackageWave` on batch queue snapshots.
- Delivery-time drift evidence persisted for IP-18.6.3 recheck.
- Apply telemetry in IP-18.6.4 must use a **read-only inbox-scoped credential**
  (`VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL` or equivalent) — not the
  writer DSN and not product-table reads.
- Production delivery (IP-18.6.3) uses `VAMO_PRODUCTION_INBOX_DATABASE_URL`
  and reuses the IP-17 builder/adapter only.
- Schema contract pinned: `vamo-place-intelligence@1`.
- No live delivery in this slice.

**Ops note (IP-18.6.2):** after applying IP-18.6.1 schema/bootstrap, re-persist or
reseed the live batch queue from fixed code before testing approvals. Verify
`staging_canary_succeeded` rows have non-null `run_report`; missing dry-run
evidence fails closed at approval time.

### IP-18.6.2 - Dashboard Approval (implemented)

- Admin + AAL2 + fresh MFA approval route/card on `/admin/ingestion`.
- Real `ingestion_audit_log` id is created first; `wave_key` and package keys
  are finalized from that id inside the control adapter.
- No delivery execution.

### IP-18.6.3 - Confirmation-Gated Delivery CLI (implemented)

- Expired approval release path: `releaseExpiredProductionPackageWaves` marks
  waves `expired`, wave items `released`, and restores queue rows to
  `staging_canary_succeeded` with audit evidence. Never touches production inbox.
- Delivery CLI: `npm --workspace @confluendo/ingestion-platform run ip18:production-package-wave`
- Preview by default; execute requires `CONFIRM_CONFLUENDO_PRODUCTION_PACKAGE_WAVE=YES`,
  `INGESTION_CONTROL_DATABASE_URL`, `VAMO_PRODUCTION_INBOX_DATABASE_URL`, and
  `VAMO_PRODUCTION_INBOX_ENVIRONMENT=production`.
- Reuses `buildProductionInboxPackage` and `deliverPostgresProductionInboxPackage`.
- Package ids/keys come from IP-18.6.2 wave item `package_key` values.
- **Delivered ≠ applied:** inbox delivery is recorded in control plane;
  Vamo-owned consumer apply remains separate (IP-18.6.4 telemetry).

Live proof (2026-07-07):

- Production package-wave approval audit id: `58`.
- Delivery audit id: `59`.
- Package id / wave key:
  `batch-production-inbox:vamo-eu-poi-sample:wave:58:unit:vamo-place-intelligence:paris-france:landmark`.
- Package checksum:
  `d696d0467e12167be8309a04fe5fc575caf38b581bb8aa307c1bffc2e8876acf`.
- Inbox items delivered: `2` (`location_canonicals`,
  `location_source_refs`), both initially pending apply.
- Vamo-owned apply result: both items `applied`, no apply errors.
- Product proof after apply: `fsq_paris_louvre_landmark` landed as
  `fsq-paris-louvre-landmark` / `Louvre Pyramid`, `feature_type=landmark`,
  `promotion_state=seeded`.
- This proof preserves the boundary: Confluendo delivered to
  `confluendo_inbox`; Vamo applied into product tables separately.

### IP-18.6.4 - Apply Telemetry (implemented)

- Read-only `confluendo_inbox_telemetry` role and adapter:
  `readPostgresProductionInboxApplyTelemetry`.
- The pooler login role (`confluendo_inbox_telemetry_app`) also needs explicit
  RLS `SELECT` policies on `confluendo_inbox.shipments`,
  `confluendo_inbox.shipment_items`, and `confluendo_inbox.apply_log`. Grants to
  the no-login group role were not enough in the live Supabase proof.
- Env: `VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL` (read-only inbox scope).
  Do not reuse `VAMO_PRODUCTION_INBOX_DATABASE_URL` writer credentials for
  dashboard/API telemetry.
- Env: `VAMO_PRODUCTION_INBOX_ENVIRONMENT=production` is also required; the
  console refuses telemetry when the production proof flag is absent.
- `refreshProductionPackageApplyTelemetry` mirrors observed inbox status into
  control-plane wave/item/queue rows and enriches `BatchQueueSnapshot`.
- `/admin/ingestion` distinguishes delivered vs consumer apply pending vs
  applied vs failed.
- **Delivered ≠ applied:** inbox delivery is recorded separately from Vamo-owned
  consumer apply.
- Delivery blocks/failures persist to control-plane wave/item/queue rows and
  audit log (`deliver_batch_production_package_wave_blocked`) so the dashboard
  shows durable truth, not only CLI output.
- Live proof (2026-07-08): package wave `58` / delivery audit `59` read back
  through the `confluendo_inbox_telemetry_app` role after adding explicit login
  role RLS policies, and the control-plane queue row advanced to
  `consumer_applied`.

### IP-18.6.5 - Delivery content equivalence (implemented)

- Pure `hashProductionPackageCandidateContent()` over deliverable candidate
  payloads (same normalization as IP-17 package assembly).
- Approval path computes `stagedContentHash` server-side per unit and persists
  it on `ingestion_batch_production_package_wave_items.staging_evidence`.
- Delivery recomputes `deliveryContentHash` before the IP-17 inbox adapter;
  blocks on mismatch or missing staged hash with IP-18.6.4 blocked-state
  persistence and audit evidence (`stagedContentHash`, `deliveryContentHash`,
  `unitKey`).
- Delivery view surfaces **Content match**, **Content drift blocked**, or
  **Hash unavailable**.

### IP-18.6.6 - Autonomy Hook

- Allow autonomy to advance production package phases only when explicitly
  permitted by policy.
- Keep first production package wave conservative until live telemetry warrants
  widening.

## First Live Vamo Run

The first live IP-18.6 Vamo run completed on 2026-07-07:

- one staging-proven unit: `vamo-place-intelligence:paris-france:landmark`;
- one fresh production package approval: audit id `58`;
- one confirmation-gated production inbox delivery: delivery audit id `59`;
- one package: `batch-production-inbox:vamo-eu-poi-sample:wave:58:unit:vamo-place-intelligence:paris-france:landmark`;
- Vamo-owned apply;
- read-only verification of canonical/source-ref rows after apply;
- apply proof: `location_canonicals:fsq-paris-louvre-landmark` and
  `location_source_refs:fsq_os_places:fsq_paris_louvre_landmark` both
  `applied`.
- apply telemetry proof: `/admin/ingestion` read the same package through the
  read-only inbox telemetry role and showed the package wave as
  `consumer_applied`.

This is a production-volume ramp proof, not the final EU corpus rollout.

## Safety Statement

IP-18.6 design does not execute production delivery. Future implementation must
preserve:

- no provider calls during package delivery;
- no Vamo staging writes;
- no direct Vamo production product-table writes;
- no browser DB credentials;
- no JavaScript checksum authority;
- no retry of spent package ids;
- consumer apply remains consumer-owned.
