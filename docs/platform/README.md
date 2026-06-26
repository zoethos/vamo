# Platform Docs

This folder holds product-independent platform architecture that is incubated in
the Vamo repo but must remain portable to a future standalone repository.

Current platform areas:

| Area | Purpose |
| --- | --- |
| `ingestion/` | Embeddable ingestion and product-cache control plane. |

Vamo-specific product specs stay in the existing Vamo folders. Platform docs
should describe reusable contracts, adapters, policy, operator controls, and
consumer profiles without making Vamo the platform boundary.
