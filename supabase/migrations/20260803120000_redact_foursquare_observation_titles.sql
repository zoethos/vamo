-- PDA-0 remediation: remove stored Foursquare place titles from user observations.
--
-- `location_provider_policies` seeds `foursquare_places_api` with
-- `can_store_content = false`, but `destination-visual` persisted the provider's
-- `title` into `location_observations.resolved_display_name` on every successful
-- visual lookup. The write path is fixed in the same change; this migration
-- clears the values already stored.
--
-- Scope safety: `supabase/functions/destination-visual/index.ts` is the only
-- writer in the repo that sets `provider = 'foursquare_places_api'` on an
-- observation, and it sourced `resolved_display_name` solely from the provider
-- response. No user-entered name can match this predicate.
--
-- Only provider content is cleared. `query_norm`, `user_id`, `trip_id`,
-- `observation_kind`, coordinates (which come from request input, not the
-- provider) and `provider_place_id` (permitted by `can_store_place_id`) are all
-- left intact, so the demand signal and the learning data survive.

do $$
declare
  v_redacted bigint;
begin
  update public.location_observations
     set resolved_display_name = null
   where provider = 'foursquare_places_api'
     and resolved_display_name is not null;

  get diagnostics v_redacted = row_count;

  raise notice 'PDA-0: redacted % Foursquare title(s) from location_observations', v_redacted;
end;
$$;
