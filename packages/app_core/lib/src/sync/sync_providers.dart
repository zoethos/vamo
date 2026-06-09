import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analytics/analytics_providers.dart';
import '../analytics/action_failure.dart';
import '../auth/auth_providers.dart';
import '../db/database_provider.dart';
import '../supabase/supabase_providers.dart';
import 'sync_coordinator.dart';
import 'sync_queue.dart';
import 'sync_worker.dart';
import 'trip_realtime.dart';

final syncQueueProvider = Provider<SyncQueue>((ref) {
  return SyncQueue(ref.watch(appDatabaseProvider));
});

final syncWorkerProvider = Provider<SyncWorker>((ref) {
  return SyncWorker(
    queue: ref.watch(syncQueueProvider),
    client: ref.watch(supabaseClientProvider),
    db: ref.watch(appDatabaseProvider),
    analytics: ref.watch(analyticsProvider),
  );
});

final tripRealtimeSubscriberProvider = Provider<TripRealtimeSubscriber>((ref) {
  final sub = TripRealtimeSubscriber(ref.watch(supabaseClientProvider));
  ref.onDispose(sub.dispose);
  return sub;
});

/// Set by feature_split to avoid a circular package dependency.
final remoteSyncGatewayProvider = Provider<RemoteSyncGateway>((ref) {
  throw UnimplementedError(
    'remoteSyncGatewayProvider must be overridden in the app shell',
  );
});

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  return SyncCoordinator(
    gateway: ref.watch(remoteSyncGatewayProvider),
    worker: ref.watch(syncWorkerProvider),
    client: ref.watch(supabaseClientProvider),
  );
});

final pendingSyncCountProvider = StreamProvider<int>((ref) {
  final queue = ref.watch(syncQueueProvider);
  final db = ref.watch(appDatabaseProvider);
  return db
      .select(db.localSyncOutbox)
      .watch()
      .asyncMap((_) => queue.countPending());
});

/// Starts connectivity + auth-driven sync. Mount once under [ProviderScope].
final syncLifecycleProvider = Provider<void>((ref) {
  final coordinator = ref.watch(syncCoordinatorProvider);
  debugBreadcrumb('mounted', screen: 'sync', action: 'sync_lifecycle');

  Future<void> runSync() async {
    debugBreadcrumb('triggered', screen: 'sync', action: 'sync_now');
    await coordinator.syncNow();
  }

  ref.listen(authStateChangesProvider, (prev, next) {
    final wasSignedIn = prev?.valueOrNull?.session != null;
    final signedIn = next.valueOrNull?.session != null;
    if (signedIn && !wasSignedIn) {
      unawaited(runSync());
    }
  });

  final connectivity = Connectivity();
  final sub = connectivity.onConnectivityChanged.listen((results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online) {
      unawaited(runSync());
    }
  });

  ref.onDispose(sub.cancel);

  unawaited(runSync());
});

/// After a local optimistic write, enqueue then try an immediate flush.
Future<void> scheduleSyncFlush(WidgetRef ref) async {
  unawaited(ref.read(syncWorkerProvider).flush());
}
