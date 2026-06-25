import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v24 includes offline pack manifest table', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 24);

    await db.upsertOfflinePack(
      LocalOfflinePacksCompanion.insert(
        tripId: 'trip-1',
        tier: OfflinePackTier.essentials.value,
        status: OfflinePackStatus.ready.value,
        createdAt: DateTime.utc(2026, 6, 25),
        updatedAt: DateTime.utc(2026, 6, 25),
        lastUpdatedAt: Value(DateTime.utc(2026, 6, 25)),
        rowCountsJson: const Value('{"trips":1,"members":1}'),
      ),
    );

    final row = await db.getOfflinePack(
      'trip-1',
      OfflinePackTier.essentials.value,
    );
    expect(row?.status, OfflinePackStatus.ready.value);
    expect(row?.rowCountsJson, contains('"members":1'));
  });

  test('v23 to v24 migration creates offline pack manifest table', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement('DROP TABLE IF EXISTS local_offline_packs');
    await db.customStatement('PRAGMA user_version = 23');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 23, 24);

    await db.upsertOfflinePack(
      LocalOfflinePacksCompanion.insert(
        tripId: 'trip-1',
        tier: OfflinePackTier.essentials.value,
        status: OfflinePackStatus.partial.value,
        createdAt: DateTime.utc(2026, 6, 25),
        updatedAt: DateTime.utc(2026, 6, 25),
        pendingOutboxCount: const Value(2),
      ),
    );

    final row = await db.getOfflinePack(
      'trip-1',
      OfflinePackTier.essentials.value,
    );
    expect(row?.status, OfflinePackStatus.partial.value);
    expect(row?.pendingOutboxCount, 2);
  });
}
