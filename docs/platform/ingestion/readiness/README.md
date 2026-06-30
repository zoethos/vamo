# Confluendo Readiness Onboarding

This folder is the onboarding path for people joining the Confluendo ingestion
platform. It is intentionally separate from Vamo product docs. Vamo is customer
zero and the running example; Confluendo is the platform boundary.

## Learning Path

| Level | Document | Audience | Outcome |
| --- | --- | --- | --- |
| 200 | `OVERVIEW_200.md` | Product, founder, PM, first-time engineer | Understand what Confluendo is, why it exists, and how Vamo uses it. |
| 400 | `USAGE_400.md` | Operator, implementation engineer, support engineer | Operate a target from proposal through dry run, staging canary, and delivery. |
| 400 | `ARCHITECTURE_DEEP_DIVE_400.md` | Platform engineer, security reviewer, future repo-split owner | Understand boundaries, runtime components, data contracts, and safety gates. |

## Start Here

1. Read `OVERVIEW_200.md` to get the product model.
2. Read `USAGE_400.md` before touching a live Confluendo instance.
3. Read `ARCHITECTURE_DEEP_DIVE_400.md` before changing platform internals,
   target adapters, shipment rules, auth, or repo boundaries.

## Source Documents

These onboarding docs are a guided entry point. The authoritative source docs
remain:

- `../ARCHITECTURE.md`
- `../TARGET_SELECTION_AND_SCHEDULING.md`
- `../DATA_DELIVERY_ARCHITECTURE.md`
- `../AUTH_ARCHITECTURE.md`
- `../STAGING_CANARY.md`
- `../STAGING_CANARY_RUNBOOK.md`
- `../bootstrap/README.md`
- `../BUILD_SLICES.md`

When an onboarding doc and a source document disagree, update the onboarding doc
or the source document in the same PR. Do not let the readiness path drift.

## Readiness Definition

A person is ready to work on Confluendo when they can explain:

- why Confluendo is not Vamo,
- how a YAML contract becomes a governed ingestion proposal,
- why dry runs, staging canaries, and production delivery are separate stages,
- which database receives each write,
- why production delivery is not a replay of staging writes,
- how audit, MFA, shipment ledgers, and target sentinels prevent accidental
  writes,
- where customer-specific files live during the in-repo incubation phase.
