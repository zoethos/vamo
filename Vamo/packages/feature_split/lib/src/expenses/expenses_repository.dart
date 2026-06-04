import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'expense_models.dart';
import 'expense_split.dart';

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return ExpensesRepository(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(supabaseClientProvider),
    analytics: ref.watch(analyticsProvider),
    fxRates: ref.watch(fxRatesClientProvider),
    syncQueue: ref.watch(syncQueueProvider),
    syncWorker: ref.watch(syncWorkerProvider),
  );
});

/// Slice 2 + 9: Drift-first; remote via sync outbox when offline.
class ExpensesRepository {
  ExpensesRepository({
    required AppDatabase db,
    required SupabaseClient client,
    required Analytics analytics,
    required FxRatesClient fxRates,
    required SyncQueue syncQueue,
    required SyncWorker syncWorker,
  })  : _db = db,
        _client = client,
        _analytics = analytics,
        _fxRates = fxRates,
        _syncQueue = syncQueue,
        _syncWorker = syncWorker;

  final AppDatabase _db;
  final SupabaseClient _client;
  final Analytics _analytics;
  final FxRatesClient _fxRates;
  final SyncQueue _syncQueue;
  final SyncWorker _syncWorker;
  final _uuid = const Uuid();

  Stream<List<ExpenseSummary>> watchTripExpenses(String tripId) {
    return _db.watchTripExpenses(tripId).map(
          (rows) => rows
              .map(
                (r) => ExpenseSummary(
                  id: r.id,
                  tripId: r.tripId,
                  description: r.description,
                  amountCents: r.amountCents,
                  baseCents: r.baseCents,
                  currency: r.currency,
                  payerId: r.payerId,
                  spentAt: r.spentAt,
                ),
              )
              .toList(),
        );
  }

  Stream<List<TripMemberView>> watchActiveMembers(String tripId) {
    return _db.watchActiveMembers(tripId).map(
          (rows) => rows
              .map(
                (m) => TripMemberView(
                  userId: m.userId,
                  displayName: m.displayName ?? 'Vamigo',
                  role: m.role,
                ),
              )
              .toList(),
        );
  }

  Future<String> addExpense({
    required AddExpenseInput input,
    required String baseCurrency,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to add an expense');
    }

    final members = await (_db.select(_db.localTripMembers)
          ..where((m) => m.tripId.equals(input.tripId))
          ..where((m) => m.status.equals('active')))
        .get();
    if (members.isEmpty) {
      throw StateError('Trip has no active members');
    }

    final expenseCurrency = input.expenseCurrency.toUpperCase();
    final tripBase = baseCurrency.toUpperCase();

    double fxRate = 1.0;
    var baseCents = input.amountCents;
    var fxStale = false;
    if (expenseCurrency != tripBase) {
      final snapshot = await _fxRates.fetchForBase(tripBase);
      fxStale = snapshot.isStale;
      fxRate = snapshot.rateExpenseToBase(expenseCurrency);
      baseCents = snapshot.toBaseCents(
        amountCents: input.amountCents,
        expenseCurrency: expenseCurrency,
      );
    }

    final shareLines = equalSplit(
      baseCents: baseCents,
      memberIds: members.map((m) => m.userId).toList(),
    );
    assertSharesSumToBase(
      baseCents: baseCents,
      shareCents: shareLines.map((s) => s.shareCents),
    );

    final expenseId = _uuid.v4();
    final spentAt = (input.spentAt ?? DateTime.now()).toUtc();
    final now = DateTime.now().toUtc();

    await _db.upsertExpense(
      LocalExpensesCompanion(
        id: Value(expenseId),
        tripId: Value(input.tripId),
        payerId: Value(input.payerId),
        amountCents: Value(input.amountCents),
        currency: Value(expenseCurrency),
        baseCents: Value(baseCents),
        fxRate: Value(fxRate),
        description: Value(input.description.trim()),
        category: Value(input.category),
        spentAt: Value(spentAt),
        createdBy: Value(userId),
        createdAt: Value(now),
      ),
    );

    final sharePayloads = <Map<String, dynamic>>[];
    for (final line in shareLines) {
      final shareId = _uuid.v4();
      await _db.upsertExpenseShare(
        LocalExpenseSharesCompanion(
          id: Value(shareId),
          expenseId: Value(expenseId),
          userId: Value(line.userId),
          shareCents: Value(line.shareCents),
        ),
      );
      sharePayloads.add({
        'id': shareId,
        'expense_id': expenseId,
        'user_id': line.userId,
        'share_cents': line.shareCents,
      });
    }

    await _syncQueue.enqueue(
      kind: SyncKind.expenseInsert,
      payload: {
        'expense': {
          'id': expenseId,
          'trip_id': input.tripId,
          'payer_id': input.payerId,
          'amount_cents': input.amountCents,
          'currency': expenseCurrency,
          'base_cents': baseCents,
          'fx_rate': fxRate,
          'description': input.description.trim(),
          'category': input.category,
          'spent_at': spentAt.toIso8601String(),
          'created_by': userId,
        },
        'shares': sharePayloads,
      },
    );
    unawaited(_syncWorker.flush());

    _analytics.capture(
      VamoEvent.expenseAdded,
      properties: {
        'trip_id': input.tripId,
        'expense_id': expenseId,
        'base_cents': baseCents,
        'member_count': members.length,
        'expense_currency': expenseCurrency,
        'fx_rate': fxRate,
        if (fxStale) 'fx_stale': true,
      },
    );

    return expenseId;
  }

  Future<void> syncExpensesForTrips(
    Iterable<String> tripIds, {
    Set<String> excludeExpenseIds = const {},
  }) async {
    final ids = tripIds.toList();
    if (ids.isEmpty) return;

    final expenseRows = await _client
        .from('expenses')
        .select(
          'id, trip_id, payer_id, amount_cents, currency, base_cents, fx_rate, '
          'description, category, spent_at, created_by, created_at',
        )
        .inFilter('trip_id', ids)
        .order('spent_at', ascending: false);

    for (final row in (expenseRows as List).cast<Map<String, dynamic>>()) {
      await _db.upsertExpense(
        LocalExpensesCompanion(
          id: Value(row['id'] as String),
          tripId: Value(row['trip_id'] as String),
          payerId: Value(row['payer_id'] as String),
          amountCents: Value((row['amount_cents'] as num).toInt()),
          currency: Value(row['currency'] as String),
          baseCents: Value((row['base_cents'] as num).toInt()),
          fxRate: Value((row['fx_rate'] as num).toDouble()),
          description: Value(row['description'] as String? ?? ''),
          category: Value(row['category'] as String?),
          spentAt: Value(DateTime.parse(row['spent_at'] as String)),
          createdBy: Value(row['created_by'] as String),
          createdAt: Value(DateTime.parse(row['created_at'] as String)),
        ),
      );
    }

    final expenseIds = (expenseRows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => r['id'] as String)
        .toList();
    if (expenseIds.isEmpty) return;

    final shareRows = await _client
        .from('expense_shares')
        .select('id, expense_id, user_id, share_cents')
        .inFilter('expense_id', expenseIds);

    for (final row in (shareRows as List).cast<Map<String, dynamic>>()) {
      await _db.upsertExpenseShare(
        LocalExpenseSharesCompanion(
          id: Value(row['id'] as String),
          expenseId: Value(row['expense_id'] as String),
          userId: Value(row['user_id'] as String),
          shareCents: Value((row['share_cents'] as num).toInt()),
        ),
      );
    }

    for (final tripId in ids) {
      final remoteIds = (expenseRows as List)
          .cast<Map<String, dynamic>>()
          .where((r) => r['trip_id'] == tripId)
          .map((r) => r['id'] as String)
          .toSet();
      await _db.pruneExpensesForTrip(
        tripId,
        remoteIds,
        excludeIds: excludeExpenseIds,
      );
    }
  }
}
