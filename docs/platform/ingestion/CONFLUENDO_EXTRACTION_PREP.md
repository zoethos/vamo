# Confluendo Extraction Prep (IP-15)

Status: prep slice for extracting Confluendo from the Vamo incubation tree.

Confluendo is the ingestion platform. Vamo is customer zero. The current code
still lives inside the `zoethos/vamo` repository, but IP-15 makes ownership,
package naming, docs, and future movement explicit before broad batch ingestion
starts.

This is **prep-only**, not the physical repo split. The standalone repo move
happens only after the boundary audit is boring and the Vamo dashboard still
works against the Confluendo-owned package namespace.

## Decisions

1. **Prep before full extraction.** Keep the code in the current monorepo for
   this slice, but make boundaries executable and documented.
2. **Console is carved out in-place before extraction.** The operator console
   lives in `web/apps/confluendo-console` as `@confluendo/console`; the Vamo
   site only redirects or links to that boundary.
3. **Package namespace changes first.** The platform workspace is named
   `@confluendo/ingestion-platform`; the Confluendo console imports it directly.
   Vamo remains a consumer through contracts, inbox/apply functions, and links
   to the console.
4. **No Vamo runtime dependency in Confluendo.** Vamo can appear as imported
   fixtures, examples, tests, runbooks, and customer-zero docs. Platform runtime
   code must not import Vamo app, Vamo web routes, Flutter packages, or Vamo
   Supabase functions.
5. **IP-18 waits for this boundary.** EU-scale batch ingestion belongs in
   Confluendo proper, not in a Vamo-shaped implementation branch.

## Current Incubation Tree

```text
Z:\vamo-ip17\                         # linked worktree of the current repo
  web/
    packages/
      ingestion-platform/              # Confluendo-owned package
    apps/
      confluendo-console/              # Confluendo-owned operator console
      site/                            # Vamo web shell, consumer handoff only
  docs/
    platform/
      ingestion/                       # Confluendo platform docs
  supabase/
    migrations/                        # Vamo-owned migrations, including inbox apply
```

The important relationship is already visible:

```text
@confluendo/console -> @confluendo/ingestion-platform
```

`@vamo/site` must not import Confluendo packages after the console carve-out.
It can link or redirect operators to the console boundary. The reverse direction
must not exist.

## Target Standalone Shape

When we create the standalone repo, the expected local shape is:

```text
Z:\confluendo\
  apps/
    console/                           # Confluendo operator console
    control-api/                       # optional service boundary
    worker/                            # worker runtime/container entrypoint
  packages/
    ingestion-platform/                # existing package, first lift
    admin-ui/                          # later shared console components
    telemetry/                         # later provider/control metrics
  docs/
    architecture/
    operations/
    auth/
    onboarding/
  sql/
    control_schema.sql
    bootstrap_template.sql
  examples/
    consumers/
      vamo-place-intelligence/         # imported snapshot, not runtime source
```

Vamo remains separate:

```text
Z:\vamo\
  contracts/
    ingestion/
      vamo-place-intelligence/
  docs/
    ingestion/
      vamo-confluendo-integration.md
  app/
  packages/
  supabase/
```

## Ownership Matrix

| Area | Owner | Lives now | Lives after extraction |
| --- | --- | --- | --- |
| Spec parser, policy engine, run planners | Confluendo | `web/packages/ingestion-platform` | `Z:\confluendo\packages\ingestion-platform` |
| Source/target adapters | Confluendo | `web/packages/ingestion-platform/adapters` | `Z:\confluendo\packages\ingestion-platform/adapters` |
| Control schema and bootstrap templates | Confluendo | `web/packages/ingestion-platform/core/sql`, docs bootstrap | `Z:\confluendo\sql`, `docs/operations` |
| Operator auth architecture and email templates | Confluendo | `docs/platform/ingestion`, `web/apps/confluendo-console` | `Z:\confluendo\apps\console`, `docs/auth` |
| Vamo consumer contract | Vamo | `Z:\vamo\contracts\ingestion\...` and imported snapshot | Vamo repo source, Confluendo example snapshot |
| Vamo product schema and apply functions | Vamo | `supabase/migrations` | Vamo repo only |
| Vamo cache metrics adapter | Confluendo customer-zero console adapter | `web/apps/confluendo-console/lib/ingestion-cache-stats.ts` | Consumer integration layer |

## Extraction Sequence

### Step 1 - Namespace and audit

Done in this prep slice:

- Rename platform package identity to `@confluendo/ingestion-platform`.
- Update Vamo web/admin imports and workspace dependency to consume that
  provider package.
- Add `ip15:boundary-audit` to catch stale `@vamo/ingestion-platform`
  references and direct platform imports from host/Vamo paths.

Command:

```powershell
npm --workspace @confluendo/ingestion-platform run ip15:boundary-audit
```

### Step 2 - Boundary inventory

Before physical extraction, classify every remaining Vamo reference:

- **allowed:** docs, runbooks, tests, imported fixtures, examples,
  customer-zero labels, Vamo host adapters;
- **not allowed:** Confluendo runtime imports from Vamo app code, Vamo web
  routes, Vamo Flutter packages, Vamo Supabase edge functions, or Vamo
  migrations.

### Step 3 - Lift package and docs

Move first:

- `web/packages/ingestion-platform` -> `Z:\confluendo\packages\ingestion-platform`
- `docs/platform/ingestion` -> `Z:\confluendo\docs`
- `tool/ingestion` and worker scripts -> `Z:\confluendo\apps\worker` or
  `Z:\confluendo\tool`

Keep the Vamo consumer web shell separate from the console; it may link or
redirect to the console but must not import platform runtime packages.

### Step 4 - Console carve-out

Done in-place before the physical repo split:

- `web/apps/confluendo-console` owns `/admin/ingestion`, `/admin/providers`,
  admin auth/MFA pages, Confluendo branding, and the server API routes for
  operator decisions.
- `web/apps/site` keeps only the Vamo landing/invite/legal shell and an
  `/admin/*` handoff route.

Vamo can then link to or embed the Confluendo console for the Vamo project
instead of hosting the console itself.

### Step 5 - Consumer integration cleanup

Vamo keeps:

- consumer contract YAML,
- Vamo production inbox migrations and apply functions,
- Vamo-specific cache metrics,
- Vamo delivery approval/runbook notes.

Confluendo keeps:

- platform code,
- open-source dataset loaders,
- batch scheduler,
- control-plane schema,
- hosted DB/API,
- reusable onboarding and bootstrap docs.

## Extraction Gates

Do not start IP-18 until these pass:

```powershell
npm --workspace @confluendo/ingestion-platform run ip15:boundary-audit
npm --workspace @confluendo/ingestion-platform test
npm --workspace @confluendo/console run build
npm --workspace @vamo/site run build
```

With disposable Postgres:

```powershell
$env:INGESTION_TEST_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:55433/postgres"
npm --workspace @confluendo/ingestion-platform test
```

The standalone repo move is ready when:

- the package namespace is Confluendo-owned,
- the boundary audit passes,
- the Confluendo console owns the admin/auth/control routes,
- the Vamo host does not import Confluendo packages and only links or redirects
  to the console,
- Vamo-specific code is either in Vamo host paths or imported consumer fixtures,
- platform tests run without reading `Z:\vamo` at runtime.

## What This Does Not Do

- It does not create the new GitHub repo yet.
- It does not move `confluendo.com` hosting yet.
- It does not automate broad EU ingestion yet.
- It does not change Vamo production data or re-run IP-17 delivery.

Those are separate slices. The immediate next implementation slice after this
prep is **IP-18 - Automated Batch Target Planning**.
