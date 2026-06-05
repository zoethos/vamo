import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../capture/capture_storage.dart';
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

/// Slice 2 + 9 + 14: Drift-first; remote via sync outbox when offline.
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

  static const _capturesBucket = StoragePaths.capturesBucket;

  Stream<List<ExpenseSummary>> watchTripExpenses(String tripId) {
    return _watchEnrichedExpenses(
      _db.watchTripExpenses(tripId),
      _db.watchTripPlaces(tripId),
    );
  }

  Stream<List<ExpenseSummary>> watchAllExpenses() {
    return _watchEnrichedExpenses(
      _db.watchAllExpenses(),
      _db.select(_db.localPlaces).watch(),
    );
  }

  Stream<List<ExpenseSummary>> _watchEnrichedExpenses(
    Stream<List<LocalExpense>> expenses$,
    Stream<List<LocalPlace>> places$,
  ) {
    return Stream.multi((controller) {
      List<LocalExpense> expenses = [];
      Map<String, LocalPlace> placesById = {};

      void emit() {
        controller.add(
          expenses
              .map((r) => _toSummary(r, placesById: placesById))
              .toList(),
        );
      }

      final subs = [
        expenses$.listen((rows) {
          expenses = rows;
          emit();
        }),
        places$.listen((rows) {
          placesById = {for (final p in rows) p.id: p};
          emit();
        }),
      ];

      controller.onCancel = () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      };
    });
  }

  ExpenseSummary _toSummary(
    LocalExpense r, {
    Map<String, LocalPlace> placesById = const {},
  }) {
    final linked = r.placeId == null ? null : placesById[r.placeId!];
    final placeLabel = linked?.label ?? r.placeLabel;
    return ExpenseSummary(
      id: r.id,
      tripId: r.tripId,
      description: r.description,
      amountCents: r.amountCents,
      baseCents: r.baseCents,
      currency: r.currency,
      payerId: r.payerId,
      spentAt: r.spentAt,
      receiptPath: r.receiptPath,
      localReceiptPath: r.localReceiptPath,
      capturedLat: r.capturedLat,
      capturedLng: r.capturedLng,
      capturedAt: r.capturedAt,
      placeLabel: placeLabel,
      placeId: r.placeId,
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

  Future<StorageAttachmentLoadResult> loadReceiptAttachment(
    ExpenseSummary expense,
  ) async {
    final local = expense.localReceiptPath;
    if (local != null && local.isNotEmpty && await File(local).exists()) {
      return StorageAttachmentLoadResult.local(local);
    }

    final remote = expense.receiptPath;
    if (remote == null || remote.isEmpty) {
      if (local != null && local.isNotEmpty && await File(local).exists()) {
        return StorageAttachmentLoadResult.local(local);
      }
      return const StorageAttachmentLoadResult.none();
    }

    final result = await CaptureStorage.cacheReceiptFromStorage(
      client: _client,
      tripId: expense.tripId,
      expenseId: expense.id,
      storagePath: remote,
    );
    if (result.isSuccess) {
      await _db.upsertExpense(
        LocalExpensesCompanion(
          id: Value(expense.id),
          localReceiptPath: Value(result.localPath),
        ),
      );
    }
    return result;
  }

  /// Back-compat alias for callers that only need a local path.
  Future<String?> resolveReceiptDisplayPath(ExpenseSummary expense) async {
    final result = await loadReceiptAttachment(expense);
    return result.localPath;
  }

  Future<AddExpenseResult> addExpense({
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

    String? localReceiptPath;
    String? receiptPath;
    if (input.receiptSourcePath != null &&
        input.receiptSourcePath!.isNotEmpty) {
      localReceiptPath = await CaptureStorage.persistReceipt(
        tripId: input.tripId,
        expenseId: expenseId,
        sourcePath: input.receiptSourcePath!,
      );
      final receiptExt = CaptureStorage.normalizeExt(
        localReceiptPath.contains('.')
            ? '.${localReceiptPath.split('.').last}'
            : '.jpg',
      );
      final targetStoragePath = StoragePaths.expenseReceipt(
        userId: userId,
        tripId: input.tripId,
        expenseId: expenseId,
        ext: receiptExt,
      );
      try {
        receiptPath = await _uploadReceipt(
          userId: userId,
          tripId: input.tripId,
          expenseId: expenseId,
          localPath: localReceiptPath,
        );
      } catch (_) {
        await _syncQueue.enqueue(
          kind: SyncKind.receiptUpload,
          payload: {
            'expense_id': expenseId,
            'local_path': localReceiptPath,
            'storage_path': targetStoragePath,
          },
        );
      }
    }

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
        receiptPath: Value(receiptPath),
        localReceiptPath: Value(localReceiptPath),
        capturedLat: Value(input.capturedLat),
        capturedLng: Value(input.capturedLng),
        capturedAt: Value(input.capturedAt?.toUtc()),
        placeLabel: Value(input.placeLabel?.trim()),
        placeId: Value(input.placeId),
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

    final expensePayload = <String, dynamic>{
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
      if (receiptPath != null) 'receipt_path': receiptPath,
      if (input.capturedLat != null) 'captured_lat': input.capturedLat,
      if (input.capturedLng != null) 'captured_lng': input.capturedLng,
      if (input.capturedAt != null)
        'captured_at': input.capturedAt!.toUtc().toIso8601String(),
      if (input.placeLabel != null && input.placeLabel!.trim().isNotEmpty)
        'place_label': input.placeLabel!.trim(),
      if (input.placeId != null && input.placeId!.isNotEmpty)
        'place_id': input.placeId,
    };

    await _syncQueue.enqueue(
      kind: SyncKind.expenseInsert,
      payload: {
        'expense': expensePayload,
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
        'has_receipt': receiptPath != null,
        'ocr_used': input.ocrUsed,
        if (fxStale) 'fx_stale': true,
      },
    );

    return AddExpenseResult(expenseId: expenseId);
  }

  Future<String> _uploadReceipt({
    required String userId,
    required String tripId,
    required String expenseId,
    required String localPath,
  }) async {
    final bytes = await File(localPath).readAsBytes();
    final ext = CaptureStorage.normalizeExt(
      localPath.contains('.') ? '.${localPath.split('.').last}' : '.jpg',
    );
    final path = StoragePaths.expenseReceipt(
      userId: userId,
      tripId: tripId,
      expenseId: expenseId,
      ext: ext,
    );
    await _client.storage.from(_capturesBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: CaptureStorage.contentTypeForPath(localPath),
            upsert: true,
          ),
        );
    return path;
  }

  Future<void> syncExpensesForTrips(
    Iterable<String> tripIds, {
    Set<String> excludeExpenseIds = const {},
  }) async {
    final ids = tripIds.toList();
    if (ids.isEmpty) return;

    const selectCols =
        'id, trip_id, payer_id, amount_cents, currency, base_cents, fx_rate, '
        'description, category, spent_at, created_by, created_at, '
        'receipt_path, captured_lat, captured_lng, captured_at, place_label, '
        'place_id';

    final expenseRows = await _client
        .from('expenses')
        .select(selectCols)
        .inFilter('trip_id', ids)
        .order('spent_at', ascending: false);

    for (final row in (expenseRows as List).cast<Map<String, dynamic>>()) {
      final expenseId = row['id'] as String;
      final tripId = row['trip_id'] as String;
      final remoteReceiptPath = row['receipt_path'] as String?;

      final existing = await (_db.select(_db.localExpenses)
            ..where((e) => e.id.equals(expenseId)))
          .getSingleOrNull();

      var localReceiptPath = existing?.localReceiptPath;
      if (remoteReceiptPath != null &&
          remoteReceiptPath.isNotEmpty &&
          (localReceiptPath == null ||
              !await File(localReceiptPath).exists())) {
        final cached = await CaptureStorage.cacheReceiptFromStorage(
          client: _client,
          tripId: tripId,
          expenseId: expenseId,
          storagePath: remoteReceiptPath,
        );
        localReceiptPath = cached.localPath;
      }

      await _db.upsertExpense(
        LocalExpensesCompanion(
          id: Value(expenseId),
          tripId: Value(tripId),
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
          receiptPath: Value(remoteReceiptPath),
          localReceiptPath: Value(localReceiptPath),
          capturedLat: Value(_nullableDouble(row['captured_lat'])),
          capturedLng: Value(_nullableDouble(row['captured_lng'])),
          capturedAt: Value(
            row['captured_at'] == null
                ? null
                : DateTime.parse(row['captured_at'] as String),
          ),
          placeLabel: Value(row['place_label'] as String?),
          placeId: Value(row['place_id'] as String?),
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

  double? _nullableDouble(Object? value) {
    if (value == null) return null;
    return (value as num).toDouble();
  }
}
