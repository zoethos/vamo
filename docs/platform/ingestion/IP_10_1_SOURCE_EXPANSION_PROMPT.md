# IP-10.1 — Real EU POI Snapshot Supply

Status: **proposed** (implementation slice). Descendant of **IP-10 "First Real
Open Dataset Source."** Chosen over an `IP-18.6` label because IP-18.6 is already
reserved for *production inbox package waves* — this slice is **supply**, not
batch orchestration.

Sequencing: **source-first before the next live wave.** IP-18.5.1/18.5.2 have
already proved the policy/execution machinery, but the first live wave failed
closed because the queue was starved. Land this before retrying IP-18.5.4 or
building IP-18.6 production inbox waves, so downstream queue/dry-run/wave slices
operate on real candidates instead of a 5-row demo fixture.

## 0. Why this slice exists (read first)

IP-18 batch planning expands `vamo-eu-poi-batch.yaml` into **36 geo/category
units** (4 countries × 9 geographies × 4 categories). The imported candidate
supply is only **5 rows, all `category: poi`, 3 cities**. Result on the live
board: 33 units have zero candidates, the 3 `poi` units show no diff, and every
unit reports `wroteToTarget=false`. **This is correct dry-run behavior, not a
failure** — the platform refused to invent rows. The fix is candidate supply, not
a code bug in the queue.

Settled decisions for this slice:

- **No live provider calls. No Google. No URL/proxy/VPN connection.** Local
  snapshot file only (`findLocalSnapshotConnectionViolations` must stay clean).
- **No Vamo staging or production writes.** This slice ends at a bounded
  **dry-run** with real candidates. Staging waves remain IP-18.5.x; the IP-16
  `applyPostgresStagingCanary` adapter stays the only staging write boundary.
- **Respect the IP-15 boundary.** No Vamo-specific policy encoded into the
  platform; `ip15:boundary-audit` output must be unchanged.
- **Media bytes stay off.** FSQ OS Places license is `canStoreMediaBytes: false`.

## A. Point the contract source at a real snapshot — `contracts/ingestion/vamo-place-intelligence/pipeline.yaml`

The imported bundle under
`web/packages/ingestion-platform/fixtures/imported/vamo-place-intelligence/` is a
**pinned, generated snapshot** (see `IMPORT_METADATA.json`). Do **not** hand-edit
it. Change the **contract source of truth** and regenerate via `import:contract`.

In `contracts/ingestion/vamo-place-intelligence/pipeline.yaml`, `source:`:

- `adapter: fixture` → `adapter: snapshot`
- `connection.fixturePath: fixtures/source.jsonl` →
  `connection.snapshotPath: fixtures/source.jsonl` (keep the snapshot local and
  inside the bundle; the file grows in §C).
- Preserve the `license:` block verbatim (attribution, `canStoreMediaBytes:
  false`, `liveOnly: false`, `canStoreFacts/Content: true`).
- Keep `cursor.strategy: monotonic_row_id`, `field: source_row_id`.

Verify against `spec/src/source-connection-policy.ts`: the connection must expose
**only** `snapshotPath` — no `url`, `proxy`, `vpn`, `headers`, `cookies`, or
rotation keys.

## B. Derive `feature_type` from category — same `pipeline.yaml` `mappings:`

**Blocker:** the mapping currently hardcodes
`- value: poi → location_canonicals.feature_type`. Even with landmark/restaurant/
transport rows, every canonical would map to `poi`. Replace the constant with a
scoped derivation:

- `- from: scope.category` → `location_canonicals.feature_type`, constrained to
  the allowlist `{ poi, landmark, restaurant, transport }`.
- Add a `qualityGate` (type `enum`/`allowed_values`, severity `block`) rejecting
  any row whose `scope.category` is outside that set, so a malformed snapshot
  cannot write an unknown `feature_type`.

If the mapping engine has no `from:` support for `feature_type` or no
value-allowlist transform, add it in `core/` with unit coverage — that transform
is the substantive engineering in this slice, not the YAML edit.

Every source row must carry `scope.geography` and `scope.category` whose keys
**match the batch-plan keys** in
`fixtures/platform/ip18/vamo-eu-poi-batch.yaml` (e.g. `rome-italy`, `italy`,
`lombardy-italy`; `poi|landmark|restaurant|transport`). Rows without matching
scope are legitimately unassignable and should surface as issues, not silent
drops.

## C. Bounded real EU sample — `contracts/ingestion/vamo-place-intelligence/fixtures/source.jsonl`

Replace the 5 demo rows with a **bounded, real, license-clean FSQ OS Places EU
sample** that spans the batch-plan scope. Requirements:

- Each row: `source.{id,name,latitude,longitude}`, `scope.{geography,category}`,
  `attribution: "FSQ Open Source Places"`. No `media.bytesBase64`.
- **Coverage target (acceptance bar):** ≥1 real candidate for every unit in the
  defined coverage set — the **9 named geographies × 4 categories** that have a
  real-world basis (city/region units). Country-rollup units (`italy/poi` etc.)
  may remain empty if the sample has no country-scoped rows; that is acceptable
  and must be stated, not hidden.
- Keep the committed sample **small but representative** (repo-fixture-tiny
  principle — target ≈ the batch-plan `sampleRowLimitPerUnit: 50`, not a full
  dump). For larger real runs, document pointing `snapshotPath` at a downloaded
  local FSQ OS Places snapshot outside the repo, keeping the same license
  metadata — mirror the guidance in `fixtures/open/fsq-os-places/README.md`.
- Preserve at least one intentional edge row (e.g. missing `name`) so the
  attribution/shape quality gates stay exercised.

## D. Regenerate and prove real candidates

Run the existing scripts (all no-network, dry-run only):

```
npm --workspace @confluendo/ingestion-platform run import:contract
npm --workspace @confluendo/ingestion-platform run ip18:batch-plan
npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed
npm --workspace @confluendo/ingestion-platform run ip18:batch-dry-run
```

Expected after run:

- `IMPORT_METADATA.json` regenerated with new `fixtures/source.jsonl` sha256 and
  `adapter: snapshot`.
- Batch dry-run reports **candidates > 0** for every unit in the coverage set,
  with `feature_type` matching the unit category (not all `poi`).
- `wroteToTarget=false` on every unit — this stays a dry-run; **no** Vamo staging
  or production writes.
- Dashboard read model (post PR #131) shows non-empty planned rows and
  readable blocker/eligibility text for the newly-populated units.

## Tests & verification

- `npm --workspace @confluendo/ingestion-platform test` (run-spec-tests) — green,
  including new `feature_type`-derivation and category-allowlist coverage.
- New/updated `adapters/source/test/*.test.ts` for snapshot rows carrying scope
  and the category→feature_type mapping.
- `npm --workspace @confluendo/ingestion-platform run ip15:boundary-audit` —
  output unchanged (no new Vamo-specific policy in the platform).
- `git diff --check`; gitleaks clean (no secrets in the snapshot).
- Live read-only spot check of the batch board confirming candidates > 0.

## Out of scope (this slice)

- Any Vamo staging or production write (that is IP-18.5.x / IP-18.6).
- Staging canary wave execution or approval flow.
- Google or any `liveOnly` source; media-byte retention.
- Non-EU geographies or new categories beyond the four in the batch plan.
- Full FSQ snapshot ingestion at scale — this slice seeds a bounded sample and
  documents the path to a larger local snapshot.

## Guardrails

- Local snapshot only; connection must pass `findLocalSnapshotConnectionViolations`.
- Do not hand-edit the pinned imported bundle — change the contract source and
  re-run `import:contract`.
- Preserve FSQ attribution and license flags exactly; `canStoreMediaBytes: false`.
- End state is a dry-run with real candidates; `wroteToTarget=false` everywhere.

## Follow-up after this lands

- Update `docs/platform/ingestion/BUILD_SLICES.md` with the real-candidate
  dry-run evidence and any remaining blocked geographies/categories.
- Reseed the live Confluendo control queue, run the bounded dry-run execution,
  then retry **IP-18.5.4**: one fresh live staging wave over a unit with real
  insert/update evidence.
