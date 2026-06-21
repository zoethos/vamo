import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _stripV11ExpenseGovernanceColumns(AppDatabase db) async {
  await db.customStatement('ALTER TABLE local_expenses DROP COLUMN status');
  await db
      .customStatement('ALTER TABLE local_expense_shares DROP COLUMN response');
  await db.customStatement(
    'ALTER TABLE local_expense_shares DROP COLUMN response_reason',
  );
  await db.customStatement(
    'ALTER TABLE local_expense_shares DROP COLUMN responded_at',
  );
}

void main() {
  test('schema v11 includes expense governance columns', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 23);

    final now = DateTime.utc(2026, 6, 5);
    await db.upsertExpense(
      LocalExpensesCompanion(
        id: const Value('e1'),
        tripId: const Value('trip-1'),
        payerId: const Value('user-1'),
        amountCents: const Value(1000),
        currency: const Value('EUR'),
        baseCents: const Value(1000),
        fxRate: const Value(1.0),
        description: const Value('Dinner'),
        spentAt: Value(now),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
        status: const Value('proposed'),
      ),
    );
    await db.upsertExpenseShare(
      LocalExpenseSharesCompanion(
        id: const Value('s1'),
        expenseId: const Value('e1'),
        userId: const Value('user-1'),
        shareCents: const Value(1000),
        response: const Value('pending'),
      ),
    );

    final expense = await db.watchTripExpenses('trip-1').first;
    final shares = await db.watchTripExpenseShares('trip-1').first;
    expect(expense.single.status, 'proposed');
    expect(shares.single.response, 'pending');
  });

  test('v10 to v11 migration step adds expense governance columns', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await _stripV11ExpenseGovernanceColumns(db);
    await db.customStatement('PRAGMA user_version = 10');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 10, 11);

    final now = DateTime.utc(2026, 6, 5);
    await db.upsertExpense(
      LocalExpensesCompanion(
        id: const Value('e1'),
        tripId: const Value('trip-1'),
        payerId: const Value('user-1'),
        amountCents: const Value(1000),
        currency: const Value('EUR'),
        baseCents: const Value(1000),
        fxRate: const Value(1.0),
        description: const Value('Dinner'),
        spentAt: Value(now),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
        status: const Value('proposed'),
      ),
    );

    final expense = await db.watchTripExpenses('trip-1').first;
    expect(expense.single.status, 'proposed');
  });
}
