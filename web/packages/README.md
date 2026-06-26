# web/packages

Shared TypeScript packages (`@vamo/*`): schema-generated types, UI primitives,
and portable platform code.

Current package namespaces:

| Path | Purpose |
| --- | --- |
| `ingestion-platform/` | Reusable ingestion/product-cache platform incubated in this repo; Vamo is the first consumer profile. |

Vamo app/admin code belongs under `web/apps/*`. Reusable ingestion runtime,
policy, spec, and adapter code belongs under `ingestion-platform/` until it is
forked into its own repository.
