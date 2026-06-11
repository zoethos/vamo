/// Product-domain entry point for app_core.
///
/// Import this for pure helpers, value objects, route/link parsing, and
/// product-neutral calculations. Keep this layer free of Drift, Supabase,
/// Riverpod, storage, analytics providers, and platform adapters.
library app_core_domain;

export 'src/analytics/analytics.dart';
export 'src/analytics/error_kind.dart';
export 'src/analytics/flow_tracker.dart';
export 'src/format/relative_time.dart';
export 'src/fx/fx_math.dart';
export 'src/fx/fx_snapshot.dart';
export 'src/invites/invite_urls.dart';
export 'src/profile/profile_models.dart';
export 'src/push/push_notification_route.dart';
export 'src/storage/storage_paths.dart';
export 'src/sync/sync_operation.dart';
export 'src/trips/trip_lifecycle.dart';
export 'src/trips/trip_member_roles.dart';
