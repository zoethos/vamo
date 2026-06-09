import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../places/places_repository.dart';
import 'receipt_metadata.dart';
import 'receipt_ocr.dart';

/// Result of a one-shot OCR backfill over cached receipt images.
class ReceiptOcrBackfillResult {
  const ReceiptOcrBackfillResult({
    required this.scanned,
    required this.updated,
    required this.placesResolved,
    required this.skipped,
    required this.failed,
  });

  final int scanned;
  final int updated;
  final int placesResolved;
  final int skipped;
  final int failed;
}

/// Runs on-device OCR over expenses that have receipts but no [place_label].
class ReceiptOcrBackfill {
  ReceiptOcrBackfill({
    required AppDatabase db,
    required SyncQueue syncQueue,
    required SyncWorker syncWorker,
    required PlacesRepository places,
  })  : _db = db,
        _syncQueue = syncQueue,
        _syncWorker = syncWorker,
        _places = places;

  final AppDatabase _db;
  final SyncQueue _syncQueue;
  final SyncWorker _syncWorker;
  final PlacesRepository _places;

  Future<ReceiptOcrBackfillResult> run() async {
    if (!receiptOcrSupported) {
      return const ReceiptOcrBackfillResult(
        scanned: 0,
        updated: 0,
        placesResolved: 0,
        skipped: 0,
        failed: 0,
      );
    }

    final rows = await (_db.select(_db.localExpenses)
          ..where(
            (e) =>
                (e.localReceiptPath.isNotNull() | e.receiptPath.isNotNull()) &
                (e.placeLabel.isNull() | e.placeLabel.equals('')),
          ))
        .get();

    var scanned = 0;
    var updated = 0;
    var placesResolved = 0;
    var skipped = 0;
    var failed = 0;

    for (final expense in rows) {
      final path = expense.localReceiptPath;
      if (path == null || path.isEmpty || !await File(path).exists()) {
        skipped++;
        continue;
      }

      scanned++;
      try {
        final suggestion = await scanReceiptImage(path);
        final place = suggestion?.merchant?.trim();
        if (place == null || place.isEmpty) {
          skipped++;
          continue;
        }

        final exif = await resolveReceiptMetadata(path);
        final capturedAt = expense.capturedAt ?? suggestion?.date?.toUtc();

        String? placeId = expense.placeId;
        if (placeId == null && suggestion != null && placeResolutionSupported) {
          final resolved = await _places.resolveFromReceipt(
            tripId: expense.tripId,
            parse: suggestion,
            exif: exif,
          );
          placeId = resolved.placeId;
          if (placeId != null) placesResolved++;
        }

        await _db.upsertExpense(
          LocalExpensesCompanion(
            id: Value(expense.id),
            placeLabel: Value(place),
            placeId: placeId == null ? const Value.absent() : Value(placeId),
            capturedAt:
                capturedAt == null ? const Value.absent() : Value(capturedAt),
          ),
        );

        final patch = <String, dynamic>{
          'id': expense.id,
          'place_label': place,
        };
        if (placeId != null) patch['place_id'] = placeId;
        if (capturedAt != null && expense.capturedAt == null) {
          patch['captured_at'] = capturedAt.toIso8601String();
        }

        await _syncQueue.enqueue(
          kind: SyncKind.expenseUpdate,
          payload: patch,
        );
        updated++;
      } catch (error, stackTrace) {
        reportAndLog(
          error,
          stackTrace,
          screen: 'receipt',
          action: 'ocr_backfill',
          severity: ActionFailureSeverity.degraded,
        );
        failed++;
      }
    }

    await _syncWorker.flush();
    return ReceiptOcrBackfillResult(
      scanned: scanned,
      updated: updated,
      placesResolved: placesResolved,
      skipped: skipped,
      failed: failed,
    );
  }
}

final receiptOcrBackfillProvider = Provider<ReceiptOcrBackfill>((ref) {
  return ReceiptOcrBackfill(
    db: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueProvider),
    syncWorker: ref.watch(syncWorkerProvider),
    places: ref.watch(placesRepositoryProvider),
  );
});
