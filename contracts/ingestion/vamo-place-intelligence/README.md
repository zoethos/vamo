# Vamo Place Intelligence — ingestion consumer contract

This bundle is **Vamo's submission to the ingestion platform**. Vamo owns it; the
platform imports a pinned snapshot and runs against that copy. The platform never
reaches into this repo at runtime.

## Contents

| File | Purpose |
| --- | --- |
| `manifest.yaml` | Ties the bundle together: consumer, profile, version, and the export file list. The platform validates this first. |
| `pipeline.yaml` | `ingestion.pipeline` spec — source, license/policy flags, cursor, field mappings, quality gates. |
| `target.yaml` | `ingestion.target` spec — the dry-run target project shape and security posture. |
| `fixtures/source.jsonl` | A small no-network sample so the platform can validate and dry-run without any provider call. |

## How it flows

1. Vamo edits and **commits** this bundle here.
2. The platform runs its import script against this directory, copying a snapshot
   into `web/packages/ingestion-platform/fixtures/imported/vamo-place-intelligence/`
   and recording this repo's commit SHA + content hashes.
3. The platform validates the snapshot with its spec kernel and dry-runs the
   fixture. Nothing here is executed by Vamo itself.

## Rules

- Paths in `manifest.yaml` are relative to this bundle and may not traverse upward.
- `pipeline.yaml` and `target.yaml` must pass the platform spec kernel
  (`ingestion.pipeline` / `ingestion.target`).
- Bump `version` in `manifest.yaml` when the contract shape changes so the platform
  import records a distinct revision.
