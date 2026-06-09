import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v15 includes member close notice columns', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 15);

    final now = DateTime.utc(2026, 6, 7);
    await db.upsertMember(
      LocalTripMembersCompanion(
        tripId: const Value('trip-1'),
        userId: const Value('user-1'),
        role: const Value('member'),
        status: const Value('active'),
        closeNotifiedAt: Value(now),
        closeRemindedAt: Value(now),
        settleNudgedAt: Value(now),
      ),
    );

    final member = await db.watchMember('trip-1', 'user-1').first;
    expect(member?.closeNotifiedAt, isNotNull);
    expect(member?.closeRemindedAt, isNotNull);
    expect(member?.settleNudgedAt, isNotNull);
  });

  test('v14 to v15 migration adds notice columns', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement(
      'ALTER TABLE local_trip_members DROP COLUMN close_notified_at',
    );
    await db.customStatement(
      'ALTER TABLE local_trip_members DROP COLUMN close_reminded_at',
    );
    await db.customStatement(
      'ALTER TABLE local_trip_members DROP COLUMN settle_nudged_at',
    );
    await db.customStatement('PRAGMA user_version = 14');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 14, 15);

    final now = DateTime.utc(2026, 6, 7);
    await db.upsertMember(
      LocalTripMembersCompanion(
        tripId: const Value('trip-1'),
        userId: const Value('user-1'),
        role: const Value('member'),
        status: const Value('active'),
        closeNotifiedAt: Value(now),
      ),
    );

    final member = await db.watchMember('trip-1', 'user-1').first;
    expect(member?.closeNotifiedAt, isNotNull);
  });
}
