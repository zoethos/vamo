import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v15 adds trip background columns', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 16);

    final now = DateTime.utc(2026, 6, 5);
    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value('trip-1'),
        name: const Value('Amalfi'),
        ownerId: const Value('owner'),
        baseCurrency: const Value('EUR'),
        backgroundPath: const Value('user/trip-1/background.jpg'),
        backgroundLocalPath: const Value('/tmp/hero.jpg'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final row = await db.watchTrip('trip-1').first;
    expect(row?.backgroundPath, 'user/trip-1/background.jpg');
    expect(row?.backgroundLocalPath, '/tmp/hero.jpg');
  });

  test('v13 to v14 migration adds background columns', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement('ALTER TABLE local_trips DROP COLUMN background_path');
    await db.customStatement(
      'ALTER TABLE local_trips DROP COLUMN background_local_path',
    );
    await db.customStatement('PRAGMA user_version = 13');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 13, 14);

    final now = DateTime.utc(2026, 6, 5);
    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value('trip-1'),
        name: const Value('Amalfi'),
        ownerId: const Value('owner'),
        baseCurrency: const Value('EUR'),
        backgroundPath: const Value('user/trip-1/background.jpg'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final row = await db.watchTrip('trip-1').first;
    expect(row?.backgroundPath, 'user/trip-1/background.jpg');
  });
}
