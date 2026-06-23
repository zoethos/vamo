# Web provider dashboard P0

## Goal

Start Vamo's web dashboard as a read-only founder view for provider health,
quota posture, and the premium-service control plane. This is the concrete
dashboard called out by:

- `docs/architecture/PROVIDER_CONTROL_PLANE.md`
- `docs/specs/premium-services-control-plane.md`
- `docs/architecture/DEPENDENCIES.md`
- `docs/AI_IDEATION_GOVERNANCE.md`

## Product decision

This is **not** the future B2B/operator console and not a user-facing trip
dashboard. It is an internal provider/cost dashboard for the founder.

## P0 scope

- Add a read-only route in `web/apps/site`: `/admin/providers`.
- Render the provider-control-plane model from static configuration:
  provider registry, quota posture, service cards, and required guardrails.
- Do not read private Supabase tables yet.
- Do not expose service-role keys to Next.js.
- Do not add mutation controls, provider switching, quota editing, password
  reset, secrets, or support actions.

## Why static first

The control-plane tables (`provider_config`, `service_usage_*`) are correctly
locked away from anon/authenticated clients. A live dashboard needs a proper
admin-auth boundary and server-side service-role access. Building the UI shell
first lets us settle information architecture and copy without punching a hole
through RLS.

## P1 scope

- Add admin authentication / authorization.
- Add a server-only data access module for service-role reads.
- Replace static cards with live rows from `provider_config`,
  `service_usage_global`, and `provider_usage_events`.
- Add audit-logged read-only exports.

## P2 scope

- Add guarded test-call controls.
- Add provider activation / rollback controls.
- Add quota editing and kill switches, each with audit logging and rollback.

## Done

- `/admin/providers` builds in `@vamo/site`.
- Page is noindexed and clearly marked read-only.
- No secrets or live service-role data are introduced.
- Docs state that this is a dashboard shell, not a privileged admin console.
