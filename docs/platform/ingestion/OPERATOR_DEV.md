# Operator Console Local Dev

The Confluendo operator console runs from `Z:\vamo-web-dashboard\web\apps\site`
on port `4373`.

Use the root helper as the mandatory local entrypoint:

```powershell
cd Z:\vamo-web-dashboard
.\Start-ConfluendoDashboard.ps1
```

or from the web workspace:

```powershell
cd Z:\vamo-web-dashboard\web
npm run dev:site:fresh
```

Do not start the site with a bare `npm --workspace @vamo/site run dev` after a
branch switch, merge, pull, rebase, or PR checkout. That can leave the running
Next.js server and `web/apps/site/.next` cache out of sync, producing errors
like `Cannot find module './901.js'` from `webpack-runtime.js`.

## Cache Policy

`Start-ConfluendoDashboard.ps1` always stops the process listening on port
`4373`, then checks the current dev state before touching the cache.

It clears `web/apps/site/.next` and `web/apps/site/.turbo` only when one of
these changes:

- Git branch.
- Git `HEAD`.
- Build inputs: `web/package-lock.json`, workspace package files,
  `web/turbo.json`, `apps/site/next.config.ts`, and related TypeScript config.
- The Confluendo dev-state marker is missing or unreadable.

The state marker lives outside `.next`, so it survives cache deletion:

```text
web/apps/site/.confluendo-dev-state.json
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
