# Confluendo Console Control Environments

The Confluendo console can operate against two independent control workspaces:

- **Staging** is the safe integration workspace. It uses the Confluendo Control
  Staging Supabase Auth project and control database. It never reads or writes
  the Vamo production inbox.
- **Production** uses the Confluendo Control Production Auth project and control
  database. It is the only workspace permitted to approve production package
  waves, inspect Vamo production-inbox telemetry, or apply delivered packages to
  Vamo.

The masthead **Workspace** selector is a server-owned context switch. It writes
only `confluendo_control_environment=staging|production` as an HTTP-only,
same-site cookie. The server maps that enum to configured credentials; database
URLs and Vamo credentials never enter browser props, the cookie, or API
responses.

## Local profiles

Keep the two ignored local profiles at the `web` root. They may also contain
the environment's artifact-store values.

`web/.env.staging.local`:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_STAGING_CONTROL_PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<staging publishable key>
INGESTION_CONTROL_DATABASE_URL=<Confluendo Control Staging app or owner DB URL>

# Trusted provisioning command only; never mapped into the console process.
CONFLUENDO_CONTROL_SUPABASE_SECRET_KEY=<staging sb_secret key>
INGESTION_CONTROL_OWNER_DATABASE_URL=<Confluendo Control Staging postgres owner URL>
```

`web/.env.production.local`:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PRODUCTION_CONTROL_PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<production publishable key>
INGESTION_CONTROL_DATABASE_URL=<Confluendo Control Production DB URL>

# Trusted provisioning command only; never mapped into the console process.
CONFLUENDO_CONTROL_SUPABASE_SECRET_KEY=<production sb_secret key>
INGESTION_CONTROL_OWNER_DATABASE_URL=<Confluendo Control Production postgres owner URL>

# Production-only server credentials, where that console capability is enabled.
VAMO_PLACE_CACHE_DATABASE_URL=<Vamo production cache read URL>
VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL=<Vamo production telemetry read URL>
VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL=<Vamo production apply URL>
VAMO_PRODUCTION_INBOX_WRITER_DATABASE_URL=<Vamo production inbox writer URL>
VAMO_PRODUCTION_INBOX_ENVIRONMENT=production
INGESTION_ADMIN_API_TOKEN=<admin API token when command routes are enabled>
```

Start a local console that loads both profiles into process-only, prefixed
settings:

```powershell
cd Z:\vamo-ip17\web
.\scripts\Start-ConfluendoConsoleControlWorkspaces.ps1 -DefaultEnvironment Staging
```

The script fails before starting if either profile is missing its Supabase URL,
public key, or control DB URL. It prints no credential values and restores the
PowerShell process environment when the dev server stops. It does not create,
copy, or commit any environment file.

Validate both profiles without starting Next.js:

```powershell
.\scripts\Start-ConfluendoConsoleControlWorkspaces.ps1 -ValidateOnly
```

## Hosted console configuration

Set these server environment variables on the Confluendo console deployment:

```dotenv
CONFLUENDO_CONTROL_DEFAULT_ENVIRONMENT=production
CONFLUENDO_CONTROL_STAGING_SUPABASE_URL=...
CONFLUENDO_CONTROL_STAGING_SUPABASE_PUBLISHABLE_KEY=...
CONFLUENDO_CONTROL_STAGING_DATABASE_URL=...
CONFLUENDO_CONTROL_PRODUCTION_SUPABASE_URL=...
CONFLUENDO_CONTROL_PRODUCTION_SUPABASE_PUBLISHABLE_KEY=...
CONFLUENDO_CONTROL_PRODUCTION_DATABASE_URL=...
CONFLUENDO_CONTROL_PRODUCTION_VAMO_PLACE_CACHE_DATABASE_URL=...
CONFLUENDO_CONTROL_PRODUCTION_VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL=...
CONFLUENDO_CONTROL_PRODUCTION_VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL=...
CONFLUENDO_CONTROL_PRODUCTION_VAMO_PRODUCTION_INBOX_WRITER_DATABASE_URL=...
CONFLUENDO_CONTROL_PRODUCTION_VAMO_PRODUCTION_INBOX_ENVIRONMENT=production
CONFLUENDO_CONTROL_PRODUCTION_INGESTION_ADMIN_API_TOKEN=...
```

The `STAGING_*` profile must not receive Vamo production credentials. A staging
route returns an explicit unavailable response if an operator attempts a
production delivery or consumer-apply action.

Use the modern **Publishable key** from Supabase's API Keys screen. It is safe
for browser configuration only when the Supabase project has Row Level Security
and appropriate policies. Existing `*_ANON_KEY` settings remain a temporary
backward-compatible fallback, but new profiles and deployments must use the
`*_PUBLISHABLE_KEY` names. Never use a Supabase Secret key in the console.

## Provision Vamo Console Administrators

Do not create an Auth user in the dashboard and then paste an allowlist query
into the SQL Editor. The trusted provisioning command owns that paired action
for the current Vamo-only authorization model:

```powershell
cd Z:\vamo-ip17\web

# Preview only: validates the requested identity and profile shape. No writes.
.\scripts\Provision-ConfluendoVamoConsoleAdmin.ps1 `
  -ControlEnvironment Staging `
  -Email "dba.confluendo@outlook.com" `
  -AuditReason "Provision the first Vamo staging console administrator."

# Creates or reuses a confirmed Supabase Auth identity, grants active Vamo
# admin access with MFA required, and records an audit event.
.\scripts\Provision-ConfluendoVamoConsoleAdmin.ps1 `
  -ControlEnvironment Staging `
  -Email "dba.confluendo@outlook.com" `
  -AuditReason "Provision the first Vamo staging console administrator." `
  -Execute
```

Production requires one additional deliberate confirmation:

```powershell
.\scripts\Provision-ConfluendoVamoConsoleAdmin.ps1 `
  -ControlEnvironment Production `
  -Email "dba.confluendo@outlook.com" `
  -AuditReason "Provision the first Vamo production console administrator." `
  -ProductionConfirmation PRODUCTION `
  -Execute
```

The command reads only the selected ignored profile. It requires
`CONFLUENDO_CONTROL_SUPABASE_SECRET_KEY` and
`INGESTION_CONTROL_OWNER_DATABASE_URL`, both of which are trusted local
provisioning credentials. They are never copied to `NEXT_PUBLIC_*` variables,
the console process, browser code, or hosted-console configuration. A repeated
call is idempotent only when the existing grant is exactly active Vamo admin
with MFA required; a conflicting grant fails closed rather than silently
changing access. This is intentionally limited to Vamo until the post-Vamo
project-membership model is implemented.

## Deliberate boundaries

- The selector does not control the hosted scheduler. The scheduler is a
  server/job capability pinned by its deployment environment, not a browser
  choice.
- Switching workspaces may require sign-in because each Supabase project owns
  a separate authenticated session.
- The selector does not promote schema or copy data. Staging and Production
  remain separate operational environments.
