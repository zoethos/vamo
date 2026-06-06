import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/plan/plan_providers.dart';
import 'package:feature_split/src/sync/trip_realtime_binding.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('trip realtime binding refreshes on every mount and unsubscribes',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final subscriber = _SpyTripRealtimeSubscriber(client);
    final coordinator = _SpySyncCoordinator(client: client, db: db);
    final container = ProviderContainer(
      overrides: [
        tripRealtimeSubscriberProvider.overrideWithValue(subscriber),
        syncCoordinatorProvider.overrideWithValue(coordinator),
      ],
    );

    final first = container.listen<void>(
      tripRealtimeBindingProvider('trip-1'),
      (_, __) {},
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);

    expect(subscriber.subscribedTripIds, ['trip-1']);
    expect(coordinator.refreshedTripIds, ['trip-1']);

    first.close();
    await Future<void>.delayed(Duration.zero);
    expect(subscriber.unsubscribedTripIds, ['trip-1']);

    final second = container.listen<void>(
      tripRealtimeBindingProvider('trip-1'),
      (_, __) {},
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);

    expect(subscriber.subscribedTripIds, ['trip-1', 'trip-1']);
    expect(coordinator.refreshedTripIds, ['trip-1', 'trip-1']);

    second.close();
    await Future<void>.delayed(Duration.zero);
    expect(subscriber.unsubscribedTripIds, ['trip-1', 'trip-1']);

    container.dispose();
    await db.close();
  });

  test('trip realtime binding reports refresh failures', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final subscriber = _SpyTripRealtimeSubscriber(client);
    final coordinator = _SpySyncCoordinator(
      client: client,
      db: db,
      refreshError: StateError('refresh failed'),
    );
    final container = ProviderContainer(
      overrides: [
        tripRealtimeSubscriberProvider.overrideWithValue(subscriber),
        syncCoordinatorProvider.overrideWithValue(coordinator),
      ],
    );
    final previousOnError = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = errors.add;

    try {
      final sub = container.listen<void>(
        tripRealtimeBindingProvider('trip-1'),
        (_, __) {},
        fireImmediately: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single.exception, isA<StateError>());

      sub.close();
      await Future<void>.delayed(Duration.zero);
      expect(subscriber.unsubscribedTripIds, ['trip-1']);
    } finally {
      FlutterError.onError = previousOnError;
      container.dispose();
      await db.close();
    }
  });

  test('mount refresh reaches Drift-backed plan provider', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final subscriber = _SpyTripRealtimeSubscriber(client);
    final gateway = _WritingGateway(db);
    final coordinator = _GatewaySyncCoordinator(
      gateway: gateway,
      client: client,
      db: db,
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        supabaseClientProvider.overrideWithValue(client),
        analyticsProvider.overrideWithValue(DebugAnalytics()),
        tripRealtimeSubscriberProvider.overrideWithValue(subscriber),
        syncCoordinatorProvider.overrideWithValue(coordinator),
      ],
    );
    final observedRemotePlan = Completer<void>();
    final planSub = container.listen(
      tripPlanItemsProvider('trip-1'),
      (_, next) {
        final rows = next.valueOrNull ?? const [];
        if (rows.any((row) => row.title == 'Remote beach day') &&
            !observedRemotePlan.isCompleted) {
          observedRemotePlan.complete();
        }
      },
      fireImmediately: true,
    );

    final bindingSub = container.listen<void>(
      tripRealtimeBindingProvider('trip-1'),
      (_, __) {},
      fireImmediately: true,
    );

    await observedRemotePlan.future.timeout(const Duration(seconds: 1));
    expect(gateway.pulledTripIds, ['trip-1']);

    bindingSub.close();
    planSub.close();
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    await db.close();
  });
}

class _SpyTripRealtimeSubscriber extends TripRealtimeSubscriber {
  _SpyTripRealtimeSubscriber(super.client);

  final subscribedTripIds = <String>[];
  final unsubscribedTripIds = <String>[];

  @override
  void subscribe(
    String tripId, {
    required Future<void> Function() onRefresh,
  }) {
    subscribedTripIds.add(tripId);
  }

  @override
  void unsubscribe(String tripId) {
    unsubscribedTripIds.add(tripId);
  }
}

class _SpySyncCoordinator extends SyncCoordinator {
  _SpySyncCoordinator({
    required SupabaseClient client,
    required AppDatabase db,
    this.refreshError,
  }) : super(
          gateway: _NoopGateway(),
          worker: SyncWorker(
            queue: SyncQueue(db),
            client: client,
            analytics: DebugAnalytics(),
            flushWithoutSession: true,
            testExecute: (_) async {},
          ),
          client: client,
        );

  final refreshedTripIds = <String>[];
  final Object? refreshError;

  @override
  Future<void> refreshTrip(String tripId) async {
    refreshedTripIds.add(tripId);
    final error = refreshError;
    if (error != null) throw error;
  }
}

class _NoopGateway implements RemoteSyncGateway {
  @override
  Future<void> pullAll() async {}

  @override
  Future<void> pullTrip(String tripId) async {}
}

class _GatewaySyncCoordinator extends SyncCoordinator {
  _GatewaySyncCoordinator({
    required RemoteSyncGateway gateway,
    required SupabaseClient client,
    required AppDatabase db,
  })  : _gateway = gateway,
        super(
          gateway: gateway,
          worker: SyncWorker(
            queue: SyncQueue(db),
            client: client,
            analytics: DebugAnalytics(),
            flushWithoutSession: true,
            testExecute: (_) async {},
          ),
          client: client,
        );

  final RemoteSyncGateway _gateway;

  @override
  Future<void> refreshTrip(String tripId) => _gateway.pullTrip(tripId);
}

class _WritingGateway implements RemoteSyncGateway {
  _WritingGateway(this._db);

  final AppDatabase _db;
  final pulledTripIds = <String>[];

  @override
  Future<void> pullAll() async {}

  @override
  Future<void> pullTrip(String tripId) async {
    pulledTripIds.add(tripId);
    final now = DateTime.utc(2026, 6, 6);
    await _db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('remote-event-1'),
        tripId: Value(tripId),
        kind: const Value('activity'),
        title: const Value('Remote beach day'),
        position: const Value(0),
        createdBy: const Value('user-remote'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }
}
