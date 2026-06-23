-- Route drafting provider routing fix.
--
-- The dashboard owns provider/model/base-url routing through provider_config.
-- Edge Function secrets stay environment-scoped and hidden, for example:
--   VAMO_OPENAI_STAGING_API_KEY
--   VAMO_OPENAI_PROD_API_KEY
--   VAMO_OPENAI_API_KEY
--   VAMO_ROUTE_DRAFT_AZURE_OPENAI_API_KEY
--
-- Keep this additive because the original Slice 2 migration may already be live.

update public.provider_config
set config = jsonb_strip_nulls(
    coalesce(config, '{}'::jsonb)
    || jsonb_build_object(
      'adapter',
      coalesce(config->>'adapter', 'openai-chat-completions'),
      'model',
      coalesce(config->>'model', 'gpt-4.1-mini'),
      'base_url',
      coalesce(config->>'base_url', 'https://api.openai.com/v1/'),
      'max_tokens',
      coalesce((config->>'max_tokens')::integer, 1400),
      'timeout_ms',
      coalesce((config->>'timeout_ms')::integer, 30000)
    )
  ),
  updated_at = now()
where service = 'draft-trip-route'
  and provider = 'openai';

comment on column public.provider_config.config is
  'Provider-specific routing/config JSON. For draft-trip-route: adapter, model, base_url, max_tokens, timeout_ms, and provider-specific options such as deployment. API keys remain Edge Function secrets.';
