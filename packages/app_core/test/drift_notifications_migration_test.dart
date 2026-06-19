import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v16 includes local notifications table', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 21);

    final now = DateTime.utc(2026, 6, 9);
    await db.upsertNotification(
      LocalNotificationsCompanion(
        id: const Value('n1'),
        userId: const Value('user-1'),
        tripId: const Value('trip-1'),
        type: const Value('close_notice'),
        title: const Value('Trip is closing'),
        body: const Value('Review balances'),
        route: const Value('/trips/trip-1/close-report'),
        createdAt: Value(now),
      ),
    );

    final rows = await db.watchNotifications('user-1').first;
    expect(rows, hasLength(1));
    expect(rows.first.title, 'Trip is closing');
    expect(rows.first.readAt, isNull);

    final unread = await db.watchUnreadNotificationCount('user-1').first;
    expect(unread, 1);
  });

  test('markNotificationReadLocal clears unread count', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const userId = 'user-1';
    await db.upsertNotification(
      LocalNotificationsCompanion(
        id: const Value('n1'),
        userId: const Value(userId),
        type: const Value('close_notice'),
        title: const Value('Trip is closing'),
        body: const Value('Review balances'),
        createdAt: Value(DateTime.utc(2026, 6, 9)),
      ),
    );

    await db.markNotificationReadLocal('n1');

    final unread = await db.watchUnreadNotificationCount(userId).first;
    expect(unread, 0);
    final row = await db.watchNotifications(userId).first;
    expect(row.first.readAt, isNotNull);
  });

  test('v15 to v16 migration adds local notifications table', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement('DROP TABLE IF EXISTS local_notifications');
    await db.customStatement('PRAGMA user_version = 15');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 15, 16);

    await db.upsertNotification(
      LocalNotificationsCompanion(
        id: const Value('n1'),
        userId: const Value('user-1'),
        type: const Value('settle_nudge'),
        title: const Value('Balance to settle'),
        body: const Value('Settle up'),
        createdAt: Value(DateTime.utc(2026, 6, 9)),
      ),
    );

    final rows = await db.watchNotifications('user-1').first;
    expect(rows, hasLength(1));
  });
}
