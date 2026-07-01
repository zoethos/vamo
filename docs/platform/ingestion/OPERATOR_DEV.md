# Operator Console Local Dev

The Confluendo operator console runs from
`Z:\vamo-web-dashboard\web\apps\confluendo-console` on port `4373`.

Use the root helper as the mandatory local entrypoint:

```powershell
cd Z:\vamo-web-dashboard
.\Start-ConfluendoDashboard.ps1
```

or from the web workspace:

```powershell
cd Z:\vamo-web-dashboard\web
npm run dev:console:fresh
```

`npm run dev:site:fresh` remains as a compatibility alias for the same helper.

On first run after the IP-15.1 carve-out, the helper copies the ignored legacy
local env file from `web/apps/site/.env.local` to
`web/apps/confluendo-console/.env.local` only when the console env file is
missing. Both files stay local-only and must not be committed.

Do not start the console with a bare
`npm --workspace @confluendo/console run dev` after a branch switch, merge,
pull, rebase, or PR checkout. That can leave the running Next.js server and
`web/apps/confluendo-console/.next` cache out of sync, producing errors like
`Cannot find module './901.js'` from `webpack-runtime.js`.

## Cache Policy

`Start-ConfluendoDashboard.ps1` always stops the process listening on port
`4373`, then checks the current dev state before touching the cache.

It clears `web/apps/confluendo-console/.next` and
`web/apps/confluendo-console/.turbo` only when one of these changes:

- Git branch.
- Git `HEAD`.
- Build inputs: `web/package-lock.json`, workspace package files,
  `web/turbo.json`, `apps/confluendo-console/next.config.ts`, and related
  TypeScript config.
- The Confluendo dev-state marker is missing or unreadable.

The state marker lives outside `.next`, so it survives cache deletion:

```text
web/apps/confluendo-console/.confluendo-dev-state.json
```

This keeps normal hot-reload work fast, while making branch/merge transitions
safe.

## Overrides

Force a clean cache:

```powershell
.\Start-ConfluendoDashboard.ps1 -ForceCacheReset
```

Skip cache reset entirely:

```powershell
.\Start-ConfluendoDashboard.ps1 -NoCacheReset
```

Use `-NoCacheReset` only for deliberate debugging. If a framework overlay or
missing chunk error appears, rerun without it.
