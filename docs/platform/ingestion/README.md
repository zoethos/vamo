# Ingestion Platform Docs

This is the documentation home for the reusable ingestion platform.

| File | Purpose |
| --- | --- |
| `ARCHITECTURE.md` | Product, runtime, policy, target-shipment, and market architecture. |
| `AUTONOMOUS_BATCH_ORCHESTRATION.md` | North-star operating model: approved sources/policy in, autonomous guarded batch runs out. |
| `AUTH_ARCHITECTURE.md` | Admin authentication, authorization, audit actor, and secret-boundary design. |
| `BUILD_SLICES.md` | Implementation slices from spec kernel through Vamo consumer profile. |
| `CONFLUENDO_EXTRACTION_PREP.md` | IP-15 prep plan: namespace, ownership, target repo shape, extraction gates. |
| `DATA_DELIVERY_ARCHITECTURE.md` | Delivery modes: consumer inbox schema and hosted Confluendo DB/API. |
| `OPERATOR_DEV.md` | Local operator-console startup and cache-reset policy for `localhost:4373`. |
| `bootstrap/README.md` | Ordered bootstrap and disaster-recovery sequence for Confluendo instances. |
| `PRODUCTION_INBOX_RUNBOOK.md` | IP-17 operational runbook: confirmation-gated production inbox delivery and Vamo-owned apply. |
| `TARGET_SELECTION_AND_SCHEDULING.md` | Target-selection criteria and AI-assisted progressive ingestion plan. |
| `STAGING_CANARY.md` | IP-16 design: promoting one reviewed dry run to a tiny, reversible, staging-only Vamo write. |
| `STAGING_CANARY_RUNBOOK.md` | IP-16 operational runbook: confirmation-gated live staging-canary execution and rollback. |

Boundary rules:

- Platform docs live here, not in Vamo-only architecture or slice folders.
- Vamo is documented as a consumer profile, not as the platform owner.
- Implementation code belongs under `web/packages/ingestion-platform/`.
- The current `/admin/ingestion` page is a Vamo admin shell that should read from
  platform APIs/read models later; it is not the platform runtime.
