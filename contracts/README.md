# Contracts

Machine-readable contracts Vamo publishes to other systems it consumes.

These are **outbound requirements**: Vamo declares what it needs, in a portable
format, and the downstream system imports a snapshot. Downstream systems must not
read this repository at runtime — they import and pin a versioned copy.

## ingestion/

Consumer contracts for the ingestion platform (the cache backfill/enrichment
supply chain). Vamo is customer zero of that platform. Each profile bundle
declares its source, target shape, policy gates, and a no-network fixture sample.

- [ingestion/vamo-place-intelligence/](ingestion/vamo-place-intelligence/README.md)

See the platform side: `Z:\vamo-web-dashboard/docs/platform/ingestion/`.
