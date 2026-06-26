# Fixtures

No-network fixture specs and data for the ingestion platform.

## Layout

- `platform/` — platform-owned test fixtures. Generic samples and malformed rows
  used by platform unit tests. Not tied to any consumer.
- `imported/` — pinned snapshots of consumer contract bundles, produced by
  `scripts/import-consumer-contract.mjs`. **Generated, not hand-edited.** Each
  `imported/<consumer>-<profile>/` carries the consumer's manifest, specs,
  fixtures, and an `IMPORT_METADATA.json` recording the source repo, commit, and
  content hashes.

## Consumer contracts are imported, not authored here

Consumers (e.g. Vamo) own their contract in their own repo and publish it as a
bundle. The platform imports a snapshot:

```bash
npm --workspace @vamo/ingestion-platform run import:contract -- \
  --from Z:/vamo/contracts/ingestion/vamo-place-intelligence
```

This keeps the platform free of any runtime dependency on a consumer repo: it
validates and runs against the pinned snapshot under `imported/`. To refresh after
a consumer changes its contract, re-run the import and commit the updated snapshot.
