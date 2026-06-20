# Security patching & dependency-vulnerability response

Status: process standard · 2026-06-06 · solo-pragmatic, scalable later
Feeds/links: `docs/architecture/DEPENDENCIES.md` (blast-radius tiers), `design/PROVIDER_RESILIENCE.md`
(runtime throttle/quota handling), `CONTRIBUTING.md` (secret rule),
`feedback` memory *credential-handling* (rotation discipline).

## Why this exists

A dependency with a critical CVE is a clock starting, not a backlog item. With
real testers on a production build, "we'll get to it" is how a known hole stays
open. This doc defines **how we hear about a vulnerability, how fast we must
act, and the safe path to ship the fix** — including the emergency case where we
drop everything. It is deliberately lightweight enough that one founder can
actually follow it under pressure; the heavier automation is marked as later.

The governing idea: **panic-patching is its own risk.** A rushed major-version
bump under pressure is how `go_router` bit us before. The process exists to make
the response *fast and calm*, not fast and reckless.

---

## 1. The model — urgency = severity × blast radius

Two axes decide how hard we jump, never severity alone:

- **Severity** — the CVE's CVSS base score (Critical ≥9.0, High 7.0–8.9,
  Medium 4.0–6.9, Low <4.0), adjusted for **reachability** (is the vulnerable
  code path actually used by us, or is it a dev-only / transitive-unused dep?).
- **Blast radius** — the dependency's tier from `docs/architecture/DEPENDENCIES.md`:
  **T0** critical-path (sign-in/sync/core), **T1** degraded (a feature breaks),
  **T2** background (no runtime impact).

A Medium in a T0 dep can outrank a High in a T2. The SLA table in §3 combines
both. Reachability first: a "Critical" in a dev-only tool you never ship is not
a production emergency — confirm before you sprint.

---

## 2. Detection — how we hear about it (layered)

**Layer 1 — automated, always-on (set up once):**

| Source | Covers | Notes |
|---|---|---|
| **Dependabot alerts** | pub (Dart), npm (web), **gradle** (Android plugins), GitHub Actions | Free on GitHub; alerts on known CVEs in the dependency graph. Enable in repo Settings → Code security. **Reads manifests/lockfiles only** — it does **not** see raw `import` URLs inside our Deno edge functions (see §2.1). |
| **Dependabot security updates** | same | Auto-opens a PR with the minimal fixing bump for an alert. |
| **Dependabot version updates** | same | Scheduled grouped PRs for routine drift (separate from security). Config in `.github/dependabot.yml`. |
| **OSV-Scanner in CI** | pub `pubspec.lock`, npm lockfiles, gradle | Second independent source (Google OSV.dev data); runs on PR + on a schedule. **Does not support Deno lockfiles** — edge functions are out of OSV scope entirely. |
| **GitHub secret scanning + push protection** | committed/pushed secrets | Catches an accidentally committed key (Supabase, Firebase JSON, Brevo, exchangerate, signing). Enable now (§9) — low-cost, high-value given our secret surface. |

**Layer 2 — manual / periodic:**

- **Quarterly dependency review** (already scheduled) — batch minor bumps, read
  the upgrade-debt list in `docs/architecture/DEPENDENCIES.md`.
- **Provider security feeds** for the non-package dependencies (Supabase,
  Vercel, Firebase, Brevo, PostHog) — these live in *no lockfile*, so scanners
  never see them. Subscribe to their status/security pages and changelogs. See §8.

### 2.1 Edge functions — exact manifests, frozen locks

Current target state: every Supabase edge function has its own
function-local `deno.json` plus committed `deno.lock`.

- Supabase recommends **one `deno.json` per function directory** for deployment
  isolation; do not replace this with a single global `/supabase/functions`
  manifest.
- Imports in `.ts` files use bare specifiers such as `@supabase/supabase-js`,
  `jose`, and `standardwebhooks`; the function-local manifest maps those to
  exact `npm:` versions.
- CI runs `deno install --frozen --entrypoint index.ts` and `deno check index.ts`
  for every function, so dependency resolution cannot drift silently.
- Dependabot Deno updates are temporarily disabled because the hosted updater
  cannot read Deno lockfile `version: "5"` yet. Until it catches up, edge
  function dependency review is manual/quarterly, backed by exact manifests,
  committed locks, and frozen CI.
- OSV stays **"no Deno lockfile coverage"** — accept it; the controls are exact
  manifests, frozen locks, and quarterly manual review of the small edge import
  surface until Dependabot can parse lockfile `version: "5"`.

---

## 3. Severity tiers & patch SLA (time-to-production)

Clock starts at **disclosure/alert**, not when we feel like it. "To production"
means the fix is live where the hole is (backend/edge in minutes; client subject
to §7 store reality).

| Severity (reachable) | T0 dep | T1 dep | T2 dep |
|---|---|---|---|
| **Critical** | **Emergency ≤ 24–48h** (§6) | ≤ 72h | ≤ 7d |
| **High** | ≤ 7d | ≤ 14d | next batch (≤30d) |
| **Medium** | ≤ 30d / next batch | next batch | quarterly |
| **Low** | quarterly batch | quarterly | quarterly |

**Not reachable** (dev-only, unused transitive path): downgrade to the
quarterly batch and record *why* it's not applicable — don't silently ignore,
and re-check if usage changes.

---

## 4. Triage — decide fast, don't panic

Four questions, in order:

1. **Is it real for us?** Is the vulnerable function/path actually used? Is it a
   runtime dep or dev-only/build-only? Transitive-but-unreachable? This single
   step prevents most fire drills.
2. **How hard do we jump?** Severity × blast-radius → SLA (§3).
3. **What's the fix path?**
   - Patch/minor available → take it (preferred — smallest change that closes
     the hole).
   - **No fix released yet** → *mitigate and watch*: config change, disable the
     feature, tighten RLS/edge validation, pin, or remove the dep. Record as a
     stopgap with a follow-up to take the real patch when it lands.
   - Only a **major** version fixes it → still scope it like a major (full smoke
     + the targeted tests, e.g. deep-link/router), even under SLA. A broken
     emergency bump is worse than the CVE. If the SLA can't be met safely,
     mitigate first (above), then do the major properly.
4. **Record it** (incident log, §11).

---

## 5. Patch → verify → deploy (the safe path, even when fast)

Even an emergency patch goes through the gate — just expedited. Non-negotiable:

- Branch (`hotfix/cve-XXXX` or `chore/dep-bump`), apply the **minimal** bump.
- `melos run ci` **green** + **cloud smoke PASS** (the standing bar).
- **Edge functions: deploy + invoke-once.** A deployed-but-never-exercised
  function is unverified — exactly how the `send-push` boot bug hid (djwt import
  that never ran). Never claim a fix on an un-invoked function.
- **Canary:** internal track / staging first, then promote to production.
- **Never skip CI for a "critical."** If CI can't run, *that* is an incident.

---

## 6. Emergency hotfix runbook (Critical, reachable, T0/T1)

The drop-everything path. Numbered so it's followable at 2am:

1. **Confirm reachability** (§4.1). A non-applicable "Critical" is not this path.
2. **Open an incident note** (§11) — timestamp, CVE, affected dep, blast radius.
3. **Branch off `main`:** `hotfix/cve-XXXX`.
4. **Minimal fix:** the patch bump, or a mitigation if no patch exists yet.
5. **Expedited gate:** `melos run ci` + cloud smoke; for edge, deploy + invoke-once.
6. **Deploy where the hole is:**
   - **Backend / edge / RLS / config** → fully in our control, live in minutes.
     This is the fast lever; prefer server-side mitigation wherever the hole can
     be closed there.
   - **Client (Flutter app)** → store + user-update lag applies (§7). Mitigate
     server-side in the meantime if at all possible.
7. **Rotate any exposed secret** immediately (credential-handling: secret store
   is canonical, verify end-to-end, revoke the old).
8. **Close out:** record the resolution; if step 4 was a stopgap, file the
   follow-up to take the real patch.

---

## 7. Mobile reality — you cannot hotfix the client instantly

A CVE in an **app-side** package can't be force-pushed to users: a fix ships at
**store-review speed + user-update lag**. Consequences for the process:

- **Prefer server-side mitigations** for client-dep CVEs — RLS, edge-function
  validation, a feature **kill-switch/flag** — to close exposure while the
  client update propagates.
- The real emergency lever for a client hole is a **minimum-supported-version
  gate** (force-update prompt that blocks old builds). We don't have one yet —
  **flagged as a W3 capability** (it pairs naturally with the notifications /
  lifecycle plumbing). Until then, client CVEs lean entirely on server-side
  mitigation + an expedited store release.
- **Backend/edge/DB are fully server-controlled** → those patch in minutes, no
  store in the loop. Push exposure to that side of the line whenever you can.

---

## 8. Provider (non-package) vulnerabilities — shared responsibility

The T0/T1 *services* (Supabase, Vercel, Firebase, Brevo, PostHog) patch their
own infrastructure; scanners never see them. Our duties:

- **Subscribe** to each provider's status + security/changelog feed (one-time).
- **Know the line:** they patch the platform; **we** patch our *config* — RLS
  policies, exposed keys, function auth, storage ACLs, SMTP/auth settings.
  A provider being secure doesn't make a misconfigured RLS policy safe.
- **Key rotation:** rotate on any suspected exposure and on a sane cadence;
  the secret store is the single canonical home (never on disk/in the repo).

---

## 9. Set up now vs. later

**Now (pragmatic, ~1 evening):**

- [ ] Enable **Dependabot alerts + security updates** (repo Settings → Code security).
- [ ] Add `.github/dependabot.yml` — ecosystems `pub`, `npm` (web),
      **`gradle`** (`/app/android`), `github-actions`; grouped, weekly (§10).
- [ ] Add **OSV-Scanner** GitHub Action — on PR + weekly schedule (§10).
- [ ] **Enable GitHub secret scanning + push protection** (repo Settings → Code
      security) **and** add the gitleaks workflow (§10) as a belt-and-suspenders
      pre-merge check. This is a *now*, not a later — our secret surface
      (Supabase keys, Firebase JSON, Brevo, exchangerate, signing) is exactly
      what it protects.
- [ ] **Commit `app/pubspec.lock`** (the shipped app) — un-ignore in `.gitignore` (§12).
- [ ] Subscribe to provider status/security feeds (§8).
- [ ] Create the incident log location (§11).

**Soon (own small chore, not "someday"):**

- [ ] **Edge-function supply chain (§2.1):** function-local `deno.json`
      manifests with **exact** versions + committed `deno.lock` files. Re-enable
      Dependabot `deno` once it supports lockfile `version: "5"`. Deploy +
      invoke-once each function after migrating.

**Later (W3, when there's reason):**

- Minimum-version **force-update gate** (the client-CVE emergency lever, §7).
- **SBOM** generation / provenance, signed releases.
- Auto-route Dependabot/OSV findings into the actionable notifications inbox
  (`design/NOTIFICATIONS.md`) so triage isn't email-only.

---

## 10. Config templates

`.github/dependabot.yml` (grouped, low-noise):

```yaml
version: 2
updates:
  # Flutter/Dart melos monorepo — root + app + every package
  - package-ecosystem: "pub"
    directories: ["/", "/app", "/packages/*"]
    schedule: { interval: "weekly" }
    groups:
      dart-minor-patch:
        update-types: ["minor", "patch"]
    open-pull-requests-limit: 5
  # npm — web tier
  - package-ecosystem: "npm"
    directories: ["/web"]
    schedule: { interval: "weekly" }
    groups:
      npm-minor-patch:
        update-types: ["minor", "patch"]
  # Android Gradle plugins (AGP, Kotlin, Google Services) in settings.gradle.kts
  - package-ecosystem: "gradle"
    directory: "/app/android"
    schedule: { interval: "weekly" }
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule: { interval: "weekly" }
```

> Verified against the actual tree: pubspecs at `/`, `/app`,
> `/packages/app_core`, `/packages/feature_split`; package.json at `/web`;
> Gradle plugins (AGP 9.0.1, Kotlin 2.3.20, Google Services 4.4.2) in
> `/app/android/settings.gradle.kts`; CI in `.github/workflows/`.
> The leftover `Vamo/` dir is gitignored, so scanners won't see it.
> Deno edge-function Dependabot is intentionally absent until GitHub's hosted
> updater supports Deno lockfile `version: "5"`.

> **Gradle caveat:** Dependabot does *version* updates for Gradle Kotlin DSL,
> but GitHub *security* alerts for Gradle need **dependency submission** (the
> dependency graph populated from a build). Version-update PRs still flow; for
> full security-alert coverage, add a dependency-submission action later.

> Security updates fire independently of this schedule. Majors come as their own
> PRs and get the scoped-chore treatment (Riverpod/go_router/Firebase) — don't
> auto-merge majors.

OSV-Scanner CI (`.github/workflows/osv-scan.yml`), PR gate + weekly:

```yaml
name: osv-scan
on:
  pull_request:
  schedule: [{ cron: "0 6 * * 1" }]   # Mondays 06:00 UTC
permissions:
  actions: read
  contents: read
  security-events: write
jobs:
  scan:
    uses: google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@v2.3.8
    with:
      scan-args: |-
        --recursive
        ./
```

Secret scanning (`.github/workflows/secret-scan.yml`) — gitleaks on PR + push,
backing up GitHub's native push protection:

```yaml
name: secret-scan
on: [pull_request, push]
permissions: { contents: read }
jobs:
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }   # full history so a secret in any commit is caught
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

> Native GitHub **secret scanning + push protection** (repo Settings → Code
> security) is the first line — it blocks a known-format secret at push time.
> gitleaks adds custom-pattern + full-history coverage as a PR gate. Run both.

---

## 11. Incident & decision log

Every actioned vulnerability gets a one-line record (where the quarterly review
can read it). Minimal shape:

```
date · CVE/advisory · dep + version · severity × tier · reachable? · action (patch/mitigate/defer) · SLA met? · notes
```

Keep it in `docs/security-log.md` (or a section here). The point is an auditable
trail: what we knew, when, and why we did what we did — the thing a real
security posture has and an ad-hoc one doesn't.

---

## 12. Lockfiles to commit (be specific — not "every lockfile everywhere")

`.gitignore` currently ignores `pubspec.lock` globally. Committing a lockfile
gives **reproducible builds** + **accurate vuln matching** (Dependabot/OSV pin
exact transitive versions from it). But the rule must name *which* lockfiles,
not become a blanket "commit every lock anywhere":

- **`app/pubspec.lock`** — **commit** (load-bearing: this is the shipped app;
  its resolution is what users actually run).
- **root `pubspec.lock`** — commit **if** root dev-tooling/CI resolution matters
  (it does here — melos/tooling); otherwise skip.
- **`packages/*/pubspec.lock`** (internal path packages) — **deliberate skip**
  by default: path-dep packages resolve through the app's lock, so their own
  locks add noise without much signal. Reconsider only if a package is consumed
  independently.
- **Edge `deno.lock` files** (§2.1) — **commit** + run CI frozen.

**Action:** un-ignore `pubspec.lock` for the app (and root), keep package locks
ignored. Then `git add app/pubspec.lock` (+ root) in your terminal.

---

## 13. Checklist (per finding)

- [ ] Reachability confirmed (real for us, not dev-only/unused)
- [ ] Severity × blast-radius → SLA assigned (§3)
- [ ] Smallest fix chosen (patch/minor preferred; major = scoped even under SLA)
- [ ] CI green + cloud smoke PASS; edge functions invoke-once verified
- [ ] Deployed where the hole is (server-side first; client via §7)
- [ ] Any exposed secret rotated + verified end-to-end
- [ ] Logged (§11); stopgaps have a follow-up to the real fix
