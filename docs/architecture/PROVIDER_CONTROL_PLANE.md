# Provider control plane

Status: design standard - 2026-06-07. Applies first to S23 theme AI, then to
the internal administrative dashboard.

## Goal

Keep Vamo's provider choices visible, swappable, and cost-aware without turning
every product feature into a provider-specific rewrite. The app should own the
contract; providers supply capacity.

## Principles

1. **Vamo-owned interface first.** Product code calls a small Vamo adapter, not
   a vendor SDK directly. Provider-specific details live behind that adapter.
2. **OpenAI-compatible contract where useful.** For LLMs, default to the
   OpenAI-compatible v1 request/response shape because OpenAI and Azure OpenAI
   both support it. That keeps Azure Foundry, direct OpenAI, and other compatible
   endpoints viable later.
3. **Configuration beats code edits.** Active provider, model/deployment,
   base URL, timeout, and budget labels are configuration. Secrets stay in the
   provider platform or Supabase function secrets, never in admin UI payloads.
4. **Telemetry is mandatory.** Every provider call emits feature, provider,
   model, cache status, latency, status, and cost/tokens when known. The admin
   dashboard reads this ledger.
5. **Switching has a gate.** A provider switch requires a test call, schema
   validation, audit log entry, and rollback path. No blind flip.

## S23 starting point

S23 theme resolution is the first producer for this standard.

- Runtime provider default: direct OpenAI.
- Runtime API shape: OpenAI-compatible strict JSON schema output.
- Neutral config names:
  - `THEME_AI_PROVIDER=openai`
  - `THEME_AI_MODEL=gpt-4.1-nano`
  - `THEME_AI_API_KEY=<secret>`
  - `THEME_AI_BASE_URL=<optional override>`
  - `THEME_AI_DEPLOYMENT=<optional Azure deployment/model override>`
- Azure-compatible future config:
  - `THEME_AI_PROVIDER=azure-openai`
  - `THEME_AI_BASE_URL=https://<resource>.openai.azure.com/openai/v1/`
  - `THEME_AI_DEPLOYMENT=<deployment name>`

The S23 Edge Function must still validate every returned theme locally. Provider
schema guarantees are helpful, not sufficient: contrast, color token safety,
tagline limits, and privacy rules remain Vamo-owned.

## Dashboard scope

The administrative dashboard should eventually provide:

- Provider registry: name, feature, active flag, model/deployment, base URL
  label, timeout, budget tag, health status, and last successful test.
- Cost and usage ledger: calls, cache hits, tokens/units, estimated USD, latency,
  errors, throttles, and quota/budget warnings.
- Switch controls: test call, activate provider, rollback to previous provider,
  and audit history.
- Secret posture: show whether the required secret is present, never show the
  secret value.

This belongs with dependency/cost monitoring, not inside feature screens.

## Non-goals

- Do not build a full dashboard for S23. S23 only needs the adapter and first
  telemetry rows/events.
- Do not abstract Supabase itself. Supabase remains the accepted high-coupling
  backbone; this standard covers replaceable external providers.
- Do not let the dashboard edit product data contracts. The adapter may switch
  providers, but the Vamo schema stays fixed.
