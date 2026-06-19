import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v21 includes expense FX harmonization columns', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 21);

    await db.upsertExpense(
      LocalExpensesCompanion(
        id: const Value('exp-fx'),
        tripId: const Value('trip-1'),
        payerId: const Value('user-a'),
        amountCents: const Value(10000),
        currency: const Value('USD'),
        baseCents: const Value(9259),
        fxRate: const Value(0.9259),
        description: const Value('FX harmonization'),
        spentAt: Value(DateTime.utc(2026, 6, 5)),
        createdBy: const Value('user-a'),
        createdAt: Value(DateTime.utc(2026, 6, 5)),
        fxRateSource: const Value('manual'),
        fxRateManual: const Value(0.9259),
        fxConversionLocked: const Value(true),
      ),
    );

    final row = await db.select(db.localExpenses).getSingle();
    expect(row.fxRateSource, 'manual');
    expect(row.fxRateManual, closeTo(0.9259, 1e-6));
    expect(row.fxConversionLocked, isTrue);
  });

  test('v20 to v21 migration adds expense FX columns with defaults', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement(
      'ALTER TABLE local_expenses DROP COLUMN fx_rate_source',
    );
    await db.customStatement(
      'ALTER TABLE local_expenses DROP COLUMN fx_rate_manual',
    );
    await db.customStatement(
      'ALTER TABLE local_expenses DROP COLUMN fx_conversion_locked',
    );
    await db.customStatement('PRAGMA user_version = 20');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 20, 21);

    await db.upsertExpense(
      LocalExpensesCompanion(
        id: const Value('legacy-exp'),
        tripId: const Value('trip-1'),
        payerId: const Value('user-a'),
        amountCents: const Value(1000),
        currency: const Value('EUR'),
        baseCents: const Value(1000),
        fxRate: const Value(1.0),
        description: const Value('legacy'),
        spentAt: Value(DateTime.utc(2026, 6, 5)),
        createdBy: const Value('user-a'),
        createdAt: Value(DateTime.utc(2026, 6, 5)),
      ),
    );

    final row = await db.select(db.localExpenses).getSingle();
    expect(row.fxRateSource, 'auto');
    expect(row.fxRateManual, null);
    expect(row.fxConversionLocked, isFalse);
  });
}
