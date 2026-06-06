import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Subscribes to Supabase Realtime while a trip is open; refreshes Drift on change.
final tripRealtimeBindingProvider =
    Provider.autoDispose.family<void, String>((ref, tripId) {
  final subscriber = ref.watch(tripRealtimeSubscriberProvider);
  final coordinator = ref.watch(syncCoordinatorProvider);

  subscriber.subscribe(
    tripId,
    onRefresh: () => _refreshTrip(coordinator, tripId),
  );

  unawaited(_refreshTrip(coordinator, tripId));

  ref.onDispose(() => subscriber.unsubscribe(tripId));
});

Future<void> _refreshTrip(SyncCoordinator coordinator, String tripId) async {
  try {
    await coordinator.refreshTrip(tripId);
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'feature_split',
        context: ErrorDescription('refreshing trip-scoped data'),
        informationCollector: () sync* {
          yield DiagnosticsProperty<String>('tripId', tripId);
        },
      ),
    );
  }
}
