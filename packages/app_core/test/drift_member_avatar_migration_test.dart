import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v22 includes local trip member avatar preference columns',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 23);

    final now = DateTime.utc(2026, 6, 19);
    await db.upsertMember(
      LocalTripMembersCompanion(
        tripId: const Value('trip-1'),
        userId: const Value('user-1'),
        role: const Value('owner'),
        status: const Value('active'),
        displayName: const Value('Alex'),
        avatarUrl: const Value('user-1/profile.jpg'),
        avatarDisplayMode: const Value('initials'),
        avatarInitials: const Value('AT'),
        completedAt: Value(now),
      ),
    );

    final rows = await db.watchActiveMembers('trip-1').first;
    expect(rows, hasLength(1));
    expect(rows.first.avatarUrl, 'user-1/profile.jpg');
    expect(rows.first.avatarDisplayMode, 'initials');
    expect(rows.first.avatarInitials, 'AT');
  });

  test('v18 to v19 migration adds local trip member avatar_url column',
      () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement('DROP TABLE IF EXISTS local_trip_members');
    await db.customStatement('''
CREATE TABLE local_trip_members (
  trip_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL,
  status TEXT NOT NULL,
  display_name TEXT NULL,
  completed_at INTEGER NULL,
  close_accepted_at INTEGER NULL,
  close_objected_at INTEGER NULL,
  close_objection_reason TEXT NULL,
  close_notified_at INTEGER NULL,
  close_reminded_at INTEGER NULL,
  settle_nudged_at INTEGER NULL,
  PRIMARY KEY (trip_id, user_id)
)
''');
    await db.customStatement('PRAGMA user_version = 18');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 18, 19);

    final columns = await db.customSelect(
      "select * from pragma_table_info('local_trip_members')",
      readsFrom: {db.localTripMembers},
    ).get();
    expect(columns.map((row) => row.data['name']), contains('avatar_url'));
  });

  test('v21 to v22 migration adds avatar preference columns', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement('DROP TABLE IF EXISTS local_trip_members');
    await db.customStatement('''
CREATE TABLE local_trip_members (
  trip_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL,
  status TEXT NOT NULL,
  display_name TEXT NULL,
  avatar_url TEXT NULL,
  completed_at INTEGER NULL,
  close_accepted_at INTEGER NULL,
  close_objected_at INTEGER NULL,
  close_objection_reason TEXT NULL,
  close_notified_at INTEGER NULL,
  close_reminded_at INTEGER NULL,
  settle_nudged_at INTEGER NULL,
  PRIMARY KEY (trip_id, user_id)
)
''');
    await db.customStatement('PRAGMA user_version = 21');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 21, 22);

    final now = DateTime.utc(2026, 6, 20);
    await db.upsertMember(
      LocalTripMembersCompanion(
        tripId: const Value('trip-1'),
        userId: const Value('user-3'),
        role: const Value('member'),
        status: const Value('active'),
        displayName: const Value('Tiziano Trocca'),
        avatarUrl: const Value('user-3/profile.jpg'),
        avatarDisplayMode: const Value('initials'),
        avatarInitials: const Value('TT'),
        completedAt: Value(now),
      ),
    );

    final rows = await db.watchActiveMembers('trip-1').first;
    expect(rows, hasLength(1));
    expect(rows.first.avatarDisplayMode, 'initials');
    expect(rows.first.avatarInitials, 'TT');
  });
}
