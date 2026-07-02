# Batch Target Planning (IP-18)

Consumer-neutral Confluendo batch planning expands a declared geography × category
matrix into deterministic dry-run target units. This slice is **planning only**:
no live scraping, no staging writes, no production inbox delivery, and no database
writes.

## Boundary

Confluendo owns the planner. Vamo is the first example consumer profile
(`vamo-place-intelligence`), not platform hard-coding. See
`CONFLUENDO_EXTRACTION_PREP.md` and `BUILD_SLICES.md` IP-15 for the extraction
boundary.

## Batch spec shape

Batch plans use `kind: ingestion.batch_plan` (YAML or JSON). Required fields:

| Field | Purpose |
| --- | --- |
| `projectKey` | Consumer project (e.g. `vamo`) |
| `sourceKey` | Dataset / source identifier |
| `targetProfileKey` | Target profile within the consumer |
| `targetKey` | **Environment-neutral** consumer target key |
| `targetEnvironment` | Explicit `staging` or `production` — never inferred from `targetKey` |
| `safetyMode` | IP-18 allows `dry_run` only |
| `geographies` | Countries, regions, cities, named areas, bounding boxes |
| `categories` | Category set to cross with geographies |
| `priorityHints` | Optional geography/category weighting |
| `bounds` | Optional `maxUnits`, `sampleRowLimitPerUnit`, `defaultBatchSize` |

Legacy environment-encoded keys such as `vamo-place-intelligence-staging` are
rejected. Unsafe modes (`staging_write`, `production_write`) fail validation.

## Planner behavior

`buildBatchPlan()` in `@confluendo/ingestion-platform/core`:

1. Expands geography × category into units with env-neutral `targetId`.
2. Deduplicates on `geography:category`.
3. Validates scope completeness; blocked units carry reasons.
4. Assigns deterministic run order (priority desc, then `unitKey` asc).
5. Optionally feeds each planned unit through existing `scoreTargetCandidate` +
   `buildScheduleProposal` when a scorecard template is supplied.

No DB, network, or provider calls.

## Vamo EU POI sample

`fixtures/platform/ip18/vamo-eu-poi-batch.yaml` is a small representative
fixture (Italy, France, Germany, Spain + a few cities/regions and categories
`poi`, `landmark`, `restaurant`, `transport`). It is **not** full EU coverage.
Later slices will source broad coverage from open snapshots (FSQ OS Places,
GeoNames, Wikidata, etc.).

## CLI dry-run

```bash
npm --workspace @confluendo/ingestion-platform run ip18:batch-plan
npm --workspace @confluendo/ingestion-platform run ip18:batch-plan -- --spec path/to/batch.yaml
```

Prints plan id, unit counts, coverage summary, first N units, and next action.
Exits non-zero on validation failure or non-`dry_run` safety mode.

## Dashboard preview

`/admin/ingestion` includes a read-only **IP-18 batch planning preview** panel
fed from bundled sample read-model data. No write or approval controls in this
slice.

## Future slices

| Slice | Scope |
| --- | --- |
| IP-18.1 | Dashboard batch queue |
| IP-18.2 | Batch dry-run persistence |
| IP-18.3 | Staged batch canaries |
| IP-18.4 | Production inbox package waves |

## Safety

IP-18.0: dry-run planning only. No live ingestion, no provider calls, no
staging or production writes.
