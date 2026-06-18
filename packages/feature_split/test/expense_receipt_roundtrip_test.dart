import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/expenses/expense_governance.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('offloaded receipt rehydrates from receiptPath', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const tripId = 'trip-1';
    const expenseId = 'expense-remote';
    const receiptPath = 'user-1/trip-1/receipts/expense-remote.jpg';
    final now = DateTime.utc(2026, 6, 19);
    final tempDir = await Directory.systemTemp.createTemp('vamo-receipt-cache');
    addTearDown(() => tempDir.delete(recursive: true));
    final cachedReceipt = File('${tempDir.path}/receipt-cache.jpg');
    await cachedReceipt.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xE0]);

    await db.upsertExpense(
      LocalExpensesCompanion(
        id: const Value(expenseId),
        tripId: const Value(tripId),
        payerId: const Value('user-1'),
        amountCents: const Value(1200),
        currency: const Value('EUR'),
        baseCents: const Value(1200),
        fxRate: const Value(1),
        description: const Value('Lunch'),
        spentAt: Value(now),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
        receiptPath: const Value(receiptPath),
      ),
    );

    final requestedPaths = <String>[];
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final repo = ExpensesRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      fxRates: FxRatesClient(),
      syncQueue: queue,
      syncWorker: SyncWorker(
        queue: queue,
        client: client,
        analytics: DebugAnalytics(),
        flushWithoutSession: true,
        testExecute: (_) async {},
      ),
      cacheReceiptFromStorage: ({
        required client,
        required tripId,
        required expenseId,
        required storagePath,
      }) async {
        requestedPaths.add(storagePath);
        return StorageAttachmentLoadResult.local(cachedReceipt.path);
      },
    );

    final result = await repo.loadReceiptAttachment(
      ExpenseSummary(
        id: expenseId,
        tripId: tripId,
        description: 'Lunch',
        amountCents: 1200,
        baseCents: 1200,
        currency: 'EUR',
        payerId: 'user-1',
        spentAt: now,
        status: ExpenseStatus.committed,
        receiptPath: receiptPath,
      ),
    );

    expect(result.localPath, cachedReceipt.path);
    expect(requestedPaths, [receiptPath]);
    expect(
      (await (db.select(db.localExpenses)..where((e) => e.id.equals(expenseId)))
              .getSingle())
          .localReceiptPath,
      cachedReceipt.path,
    );
  });
}
