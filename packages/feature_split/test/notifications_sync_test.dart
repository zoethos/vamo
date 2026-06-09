import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/notifications/notifications_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postgrest/postgrest.dart';

import 'trips_repository_test_support.dart';

class _SpyNotificationsRepository extends NotificationsRepository {
  _SpyNotificationsRepository({
    required super.db,
    required super.client,
  });

  int syncFromRemoteCalls = 0;

  @override
  Future<void> syncFromRemote() async {
    syncFromRemoteCalls++;
  }
}

void main() {
  test('syncTripFromRemote pulls user-scoped notifications', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final client = await createSignedInTestClient('user-1');
    final notifications = _SpyNotificationsRepository(db: db, client: client);
    final repo = buildTestTripsRepository(
      db,
      client: client,
      notifications: notifications,
    );

    await expectLater(
      repo.syncTripFromRemote('trip-targeted-sync'),
      throwsA(isA<PostgrestException>()),
    );
    expect(notifications.syncFromRemoteCalls, 1);
  });

  test('clearLocal removes cached notifications on sign-out', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.upsertNotification(
      LocalNotificationsCompanion(
        id: const Value('n1'),
        userId: const Value('user-1'),
        type: const Value('close_notice'),
        title: const Value('Trip is closing'),
        body: const Value('Review balances'),
        createdAt: Value(DateTime.utc(2026, 6, 9)),
      ),
    );

    final repo = buildTestTripsRepository(db);
    await repo.clearLocal();

    final rows = await db.watchNotifications('user-1').first;
    expect(rows, isEmpty);
  });
}
