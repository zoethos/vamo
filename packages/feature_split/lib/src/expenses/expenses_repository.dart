import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../capture/capture_storage.dart';
import 'expense_governance.dart';
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

typedef ReceiptCacheLoader = Future<StorageAttachmentLoadResult> Function({
  required SupabaseClient client,
  required String tripId,
  required String expenseId,
  required String storagePath,
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
    ReceiptCacheLoader? cacheReceiptFromStorage,
  })  : _db = db,
        _client = client,
        _analytics = analytics,
        _fxRates = fxRates,
        _syncQueue = syncQueue,
        _syncWorker = syncWorker,
        _cacheReceiptFromStorage =
            cacheReceiptFromStorage ?? CaptureStorage.cacheReceiptFromStorage;

  final AppDatabase _db;
  final SupabaseClient _client;
  final Analytics _analytics;
  // Kept for provider wiring; expense writes use trip constant-rate table (S20).
  // ignore: unused_field
  final FxRatesClient _fxRates;
  final SyncQueue _syncQueue;
  final SyncWorker _syncWorker;
  final ReceiptCacheLoader _cacheReceiptFromStorage;
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
          expenses.map((r) => _toSummary(r, placesById: placesById)).toList(),
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
      category: r.category,
      status: ExpenseStatus.parse(r.status),
      fxRateSource: r.fxRateSource,
      fxRateManual: r.fxRateManual,
      fxConversionLocked: r.fxConversionLocked,
    );
  }

  Stream<List<ExpenseShareSummary>> watchTripExpenseShares(String tripId) {
    return _db.watchTripExpenseShares(tripId).map(
          (rows) => rows.map(_toShareSummary).toList(),
        );
  }

  ExpenseShareSummary _toShareSummary(LocalExpenseShare row) =>
      ExpenseShareSummary(
        id: row.id,
        expenseId: row.expenseId,
        userId: row.userId,
        shareCents: row.shareCents,
        response: ShareResponse.parse(row.response),
        responseReason: row.responseReason,
        respondedAt: row.respondedAt,
      );

  Stream<List<TripMemberView>> watchActiveMembers(String tripId) {
    return _db.watchActiveMembers(tripId).map(
          (rows) => rows
              .map(
                (m) => TripMemberView(
                  userId: m.userId,
                  displayName: m.displayName ?? 'Vamigo',
                  role: m.role,
                  avatarUrl: m.avatarUrl,
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

    final result = await _cacheReceiptFromStorage(
      client: _client,
      tripId: expense.tripId,
      expenseId: expense.id,
      storagePath: remote,
    );
    if (result.isSuccess) {
      await _db.updateExpenseFields(
        expense.id,
        LocalExpensesCompanion(localReceiptPath: Value(result.localPath)),
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
    if (expenseCurrency != tripBase) {
      if (input.manualBaseCents != null && input.manualBaseCents! > 0) {
        baseCents = input.manualBaseCents!;
        fxRate = fxRateFromReceiptTotals(
          amountCents: input.amountCents,
          receiptBaseCents: baseCents,
        );
      } else {
        final resolved = await _resolveTripFxRate(
          tripId: input.tripId,
          expenseCurrency: expenseCurrency,
          tripBase: tripBase,
          amountCents: input.amountCents,
        );
        fxRate = resolved.fxRate;
        baseCents = resolved.baseCents;
      }
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
      } catch (error, stackTrace) {
        reportAndLog(
          error,
          stackTrace,
          screen: 'expense',
          action: 'upload_receipt_remote',
          severity: ActionFailureSeverity.degraded,
          analytics: _analytics,
        );
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
        status: const Value('committed'),
        fxRateSource: const Value('auto'),
        fxConversionLocked: const Value(false),
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
          response: const Value('accepted'),
        ),
      );
      sharePayloads.add({
        'id': shareId,
        'expense_id': expenseId,
        'user_id': line.userId,
        'share_cents': line.shareCents,
        'response': 'accepted',
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
      'status': 'committed',
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
    await _syncWorker.flush();

    await _applyFxAmendIfNeeded(
      expenseId: expenseId,
      tripId: input.tripId,
      amountCents: input.amountCents,
      baseCents: baseCents,
      fxRate: fxRate,
      fxRateSource: input.fxRateSource,
      fxRateManual: input.fxRateSource == 'receipt' ? fxRate : null,
      lockConversion: input.lockConversion ||
          input.manualBaseCents != null ||
          input.fxRateSource == 'receipt',
    );

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
        'fx_rate_source, fx_rate_manual, fx_conversion_locked, '
        'description, category, spent_at, created_by, created_at, status, '
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
        final cached = await _cacheReceiptFromStorage(
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
          fxRateSource: Value(row['fx_rate_source'] as String? ?? 'auto'),
          fxRateManual: Value(_nullableDouble(row['fx_rate_manual'])),
          fxConversionLocked: Value(
            row['fx_conversion_locked'] as bool? ?? false,
          ),
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
          status: Value((row['status'] as String?) ?? 'committed'),
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
        .select(
          'id, expense_id, user_id, share_cents, response, response_reason, responded_at',
        )
        .inFilter('expense_id', expenseIds);

    for (final row in (shareRows as List).cast<Map<String, dynamic>>()) {
      await _db.upsertExpenseShare(
        LocalExpenseSharesCompanion(
          id: Value(row['id'] as String),
          expenseId: Value(row['expense_id'] as String),
          userId: Value(row['user_id'] as String),
          shareCents: Value((row['share_cents'] as num).toInt()),
          response: Value((row['response'] as String?) ?? 'accepted'),
          responseReason: Value(row['response_reason'] as String?),
          respondedAt: Value(_nullableDate(row['responded_at'])),
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

  DateTime? _nullableDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value as String)?.toUtc();
  }

  Future<({double fxRate, int baseCents})> _resolveTripFxRate({
    required String tripId,
    required String expenseCurrency,
    required String tripBase,
    required int amountCents,
  }) async {
    final expense = expenseCurrency.toUpperCase();
    final base = tripBase.toUpperCase();
    if (expense == base) {
      return (fxRate: 1.0, baseCents: amountCents);
    }
    final row = await (_db.select(_db.localTripFxRates)
          ..where((r) => r.tripId.equals(tripId))
          ..where((r) => r.currency.equals(expense)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Trip FX rate missing for $expense');
    }
    final baseCents = convertExpenseCentsToBase(
      amountCents: amountCents,
      fxRate: row.rate,
    );
    return (fxRate: row.rate, baseCents: baseCents);
  }

  Future<({double fxRate, int baseCents})> resolveTripFxRateForExpense({
    required String tripId,
    required String expenseCurrency,
    required String tripBase,
    required int amountCents,
  }) =>
      _resolveTripFxRate(
        tripId: tripId,
        expenseCurrency: expenseCurrency,
        tripBase: tripBase,
        amountCents: amountCents,
      );

  Future<void> amendExpenseConversion({
    required String expenseId,
    required int baseCents,
    required String fxRateSource,
    double? fxRate,
    double? fxRateManual,
    bool lock = true,
  }) async {
    await _client.rpc('amend_expense_conversion', params: {
      'p_expense_id': expenseId,
      'p_base_cents': baseCents,
      if (fxRate != null) 'p_fx_rate': fxRate,
      'p_fx_rate_source': fxRateSource,
      if (fxRateManual != null) 'p_fx_rate_manual': fxRateManual,
      'p_lock': lock,
    });

    final existing = await (_db.select(_db.localExpenses)
          ..where((e) => e.id.equals(expenseId)))
        .getSingleOrNull();
    if (existing != null) {
      await syncExpensesForTrips([existing.tripId]);
    }
  }

  Future<void> _applyFxAmendIfNeeded({
    required String expenseId,
    required String tripId,
    required int amountCents,
    required int baseCents,
    required double fxRate,
    String? fxRateSource,
    double? fxRateManual,
    required bool lockConversion,
  }) async {
    final source = fxRateSource;
    if (!lockConversion && (source == null || source == 'auto')) return;

    await amendExpenseConversion(
      expenseId: expenseId,
      baseCents: baseCents,
      fxRate: fxRate,
      fxRateSource: source ?? 'manual',
      fxRateManual: fxRateManual,
      lock: lockConversion,
    );
  }

  Future<String> proposeExpense({
    required String tripId,
    required String payerId,
    required String description,
    required int amountCents,
    required String currency,
    required int baseCents,
    required double fxRate,
    String? category,
    int? manualBaseCents,
    String? fxRateSource,
    bool lockConversion = false,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Must be signed in');

    final members = await (_db.select(_db.localTripMembers)
          ..where((m) => m.tripId.equals(tripId))
          ..where((m) => m.status.equals('active')))
        .get();
    if (members.isEmpty) throw StateError('Trip has no active members');

    final shareLines = equalSplit(
      baseCents: baseCents,
      memberIds: members.map((m) => m.userId).toList(),
    );
    assertSharesSumToBase(
      baseCents: baseCents,
      shareCents: shareLines.map((s) => s.shareCents),
    );

    final expenseId = _uuid.v4();

    await _client.rpc('propose_expense', params: {
      'p_id': expenseId,
      'p_trip_id': tripId,
      'p_payer_id': payerId,
      'p_amount_cents': amountCents,
      'p_currency': currency,
      'p_base_cents': baseCents,
      'p_fx_rate': fxRate,
      'p_description': description.trim(),
      'p_category': category,
    });

    await _applyFxAmendIfNeeded(
      expenseId: expenseId,
      tripId: tripId,
      amountCents: amountCents,
      baseCents: manualBaseCents ?? baseCents,
      fxRate: manualBaseCents == null
          ? fxRate
          : fxRateFromReceiptTotals(
              amountCents: amountCents,
              receiptBaseCents: manualBaseCents,
            ),
      fxRateSource: fxRateSource,
      fxRateManual: fxRateSource == 'receipt' && manualBaseCents != null
          ? fxRateFromReceiptTotals(
              amountCents: amountCents,
              receiptBaseCents: manualBaseCents,
            )
          : null,
      lockConversion:
          lockConversion || manualBaseCents != null || fxRateSource == 'receipt',
    );

    await syncExpensesForTrips([tripId]);

    _analytics.capture(
      VamoEvent.proposalCreated,
      properties: {'trip_id': tripId},
    );

    return expenseId;
  }

  /// Updates expense category locally and queues remote patch (S40).
  Future<void> updateExpenseCategory({
    required String expenseId,
    required String? category,
  }) async {
    await _db.upsertExpense(
      LocalExpensesCompanion(
        id: Value(expenseId),
        category: Value(category),
      ),
    );
    await _syncQueue.enqueue(
      kind: SyncKind.expenseUpdate,
      payload: {
        'id': expenseId,
        'category': category,
      },
    );
    unawaited(_syncWorker.flush());
  }

  Future<void> commitExpense(String expenseId) async {
    final existing = await (_db.select(_db.localExpenses)
          ..where((e) => e.id.equals(expenseId)))
        .getSingleOrNull();
    if (existing == null) return;

    await _client.rpc('commit_expense', params: {'p_expense_id': expenseId});
    await _db.upsertExpense(
      LocalExpensesCompanion(
        id: Value(expenseId),
        status: const Value('committed'),
      ),
    );

    _analytics.capture(
      VamoEvent.proposalCommitted,
      properties: {'trip_id': existing.tripId},
    );
  }

  Future<void> voidExpense(String expenseId) async {
    final existing = await (_db.select(_db.localExpenses)
          ..where((e) => e.id.equals(expenseId)))
        .getSingleOrNull();
    if (existing == null) return;

    await _client.rpc('void_expense', params: {'p_expense_id': expenseId});
    await _db.upsertExpense(
      LocalExpensesCompanion(
        id: Value(expenseId),
        status: const Value('cancelled'),
      ),
    );

    _analytics.capture(
      VamoEvent.proposalCancelled,
      properties: {'trip_id': existing.tripId},
    );
  }

  Future<void> respondToShare({
    required String expenseId,
    required bool accept,
    String? reason,
  }) async {
    final existing = await (_db.select(_db.localExpenses)
          ..where((e) => e.id.equals(expenseId)))
        .getSingleOrNull();
    if (existing == null) return;

    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Must be signed in');

    await _client.rpc('respond_to_share', params: {
      'p_expense_id': expenseId,
      'p_accept': accept,
      'p_reason': reason,
    });

    final share = await (_db.select(_db.localExpenseShares)
          ..where((s) => s.expenseId.equals(expenseId))
          ..where((s) => s.userId.equals(userId)))
        .getSingleOrNull();
    if (share == null) {
      await syncExpensesForTrips([existing.tripId]);
      return;
    }

    final now = DateTime.now().toUtc();
    await _db.upsertExpenseShare(
      LocalExpenseSharesCompanion(
        id: Value(share.id),
        response: Value(accept ? 'accepted' : 'rejected'),
        responseReason: accept ? const Value(null) : Value(reason?.trim()),
        respondedAt: Value(now),
      ),
    );

    _analytics.capture(
      VamoEvent.shareResponse,
      properties: {
        'trip_id': existing.tripId,
        'response': accept ? 'accepted' : 'rejected',
        'has_reason': !accept && (reason?.trim().isNotEmpty ?? false),
      },
    );
  }
}
