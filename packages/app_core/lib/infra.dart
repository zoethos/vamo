/// Infrastructure entry point for app_core.
///
/// Import this when a surface intentionally needs providers, repositories,
/// database, Supabase, sync, storage loading, analytics adapters, routing, or
/// platform-facing services.
library app_core_infra;

export 'src/analytics/action_error_ui.dart';
export 'src/analytics/action_failure.dart';
export 'src/analytics/analytics_providers.dart';
export 'src/analytics/navigation_observer.dart';
export 'src/analytics/posthog_analytics.dart';
export 'src/auth/auth_providers.dart';
export 'src/auth/auth_repository.dart';
export 'src/auth/auth_urls.dart';
export 'src/db/app_database.dart';
export 'src/db/database_provider.dart';
export 'src/env/env.dart';
export 'src/fx/fx_providers.dart';
export 'src/fx/fx_rates_client.dart';
export 'src/locale/locale_providers.dart';
export 'src/profile/profile_providers.dart';
export 'src/profile/profile_repository.dart';
export 'src/push/push_registrar.dart';
export 'src/router/app_router.dart';
export 'src/router/route_not_found.dart';
export 'src/storage/storage_attachment_load.dart';
export 'src/suggestions/suggestions_repository.dart';
export 'src/supabase/supabase_providers.dart';
export 'src/sync/sync_coordinator.dart';
export 'src/sync/sync_providers.dart';
export 'src/sync/sync_queue.dart';
export 'src/sync/sync_worker.dart';
export 'src/sync/trip_realtime.dart';
