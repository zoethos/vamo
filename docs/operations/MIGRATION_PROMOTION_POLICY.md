# Migration Promotion Policy

Status: mandatory governance for all agents and operators touching Supabase
migrations, RPCs, RLS policies, edge-function database contracts, or target
schema used by Vamo.

Purpose: staging is where we prove migrations; production is where we keep the
product honest. A migration is not complete just because staging is green. From
now on, every schema-affecting slice must explicitly track the path:

```text
local migration -> staging apply -> staging smoke -> production promotion -> production verification
```

## Policy

1. **Staging first, production close behind.**
   - Every migration must be applied to staging before production.
   - Once staging is green, production promotion must be planned immediately.
   - Production should normally be promoted in the same release window.

2. **Maximum allowed drift.**
   - Production may lag staging by at most **one intentional migration batch**.
   - A migration batch is the set of migrations for one feature/fix slice.
   - Do not start a second schema-affecting batch while the previous
     staging-green batch is still unpromoted, unless the handoff names an
     explicit blocker and owner.
   - If a staging-green migration cannot be promoted within **7 days**, open a
     blocker note/issue and call it out in every related handoff until closed.

3. **Environment-specific objects are not promoted blindly.**
   - App schema, RLS policies, RPCs, indexes, and seed data needed by the app
     move staging -> production through this policy.
   - Staging-only operational objects do **not** move to production. Examples:
     canary roles, staging sentinels, staging-only debug grants, and bounded
     Confluendo write roles.
   - Production must never receive a staging proof such as a sentinel row with
     `value='staging'`.

4. **Staging green means evidence, not vibes.**
   - For Supabase schema/RLS work, staging green requires:
     - migration applied to staging,
     - relevant verification SQL recorded,
     - cloud RLS smoke or targeted smoke green,
     - rollback/forward-fix posture named.
   - A compile-only check is not enough for database changes.

5. **Production promotion requires verification.**
   - After production apply, run the same structural verification queries used
     on staging.
   - Run production-safe smoke checks only. Do not run staging load tests,
     destructive checks, or provider-cost checks against production.
   - Record the production verification result in the handoff.

## Required Agent Checkpoint

Every agent handoff for a schema-affecting slice must include this block:

```text
Migration promotion checkpoint:
- Migration files changed:
- Staging project/ref:
- Staging apply status:
- Staging verification/smoke:
- Production project/ref:
- Production apply status:
- Production verification:
- Current drift:
- If production not promoted: blocker, owner, planned date, and why drift is acceptable:
- Environment-specific objects excluded from production:
```

Allowed `Production apply status` values:

- `not_applicable` - no database/schema impact.
- `promoted_and_verified` - production is aligned and verification is green.
- `pending_same_release_window` - staging is green and production is scheduled
  in the current release window.
- `blocked_with_owner` - production is intentionally not promoted; blocker,
  owner, and date are named.

Do not use vague statuses such as `later`, `soon`, or `deferred`.

## Operator Checklist

Use this checklist when a migration is ready:

1. Confirm the migration file(s) and branch.
2. Apply to staging.
3. Run staging verification SQL.
4. Run cloud RLS smoke or targeted smoke.
5. If staging is green, decide immediately:
   - promote to production now, or
   - record a named blocker with owner/date.
6. Apply the same app schema migration batch to production.
7. Run production structural verification.
8. Run production-safe smoke only.
9. Update the handoff with the checkpoint block.

## Drift Review Cadence

At least once per active development week, run a migration drift review:

```text
- List migrations present locally.
- List migrations applied on staging.
- List migrations applied on production.
- Identify any staging-only migration batch.
- Promote or document blocker/owner/date.
```

For solo-founder speed, this can be lightweight, but it must be explicit. The
goal is not bureaucracy; it is avoiding a quiet gap where staging works and
production is unknowingly missing the schema.

## Special Case: Confluendo And Vamo

Confluendo is the ingestion platform. Vamo is customer zero and a consumer.

For Confluendo-driven Vamo ingestion:

- Vamo app schema migrations, such as place-intelligence cache tables, should
  be promoted staging -> production under this policy.
- Confluendo staging canary enablement remains staging-only:
  - `confluendo_guard.environment_sentinel`,
  - `vamo_canary_app`,
  - canary-specific grants/RLS policies.
- Production may receive the Vamo app schema, but not Confluendo staging-write
  permissions.

This preserves two invariants at once: production is schema-aligned for the app,
and Confluendo canary writes remain structurally impossible against production.
