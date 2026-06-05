import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  LocalTrips,
  LocalTripMembers,
  LocalExpenses,
  LocalExpenseShares,
  LocalSettlements,
  LocalTripNotes,
  LocalTripPhotos,
  LocalSyncOutbox,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory Drift for unit tests (persistence / query behavior).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(localExpenses);
            await m.createTable(localExpenseShares);
            await m.addColumn(
              localTripMembers,
              localTripMembers.displayName,
            );
          }
          if (from < 3) {
            await m.createTable(localSettlements);
          }
          if (from < 4) {
            await m.createTable(localTripNotes);
            await m.createTable(localTripPhotos);
          }
          if (from < 5) {
            await m.createTable(localSyncOutbox);
          }
          if (from < 6) {
            await m.addColumn(localExpenses, localExpenses.receiptPath);
            await m.addColumn(localExpenses, localExpenses.localReceiptPath);
            await m.addColumn(localExpenses, localExpenses.capturedLat);
            await m.addColumn(localExpenses, localExpenses.capturedLng);
            await m.addColumn(localExpenses, localExpenses.capturedAt);
          }
        },
      );

  Stream<List<LocalTrip>> watchAllTrips() {
    return (select(localTrips)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Stream<LocalTrip?> watchTrip(String id) {
    return (select(localTrips)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  Stream<int> watchActiveMemberCount(String tripId) {
    return (select(localTripMembers)
          ..where((m) => m.tripId.equals(tripId))
          ..where((m) => m.status.equals('active')))
        .watch()
        .map((rows) => rows.length);
  }

  Stream<List<LocalTripMember>> watchActiveMembers(String tripId) {
    return (select(localTripMembers)
          ..where((m) => m.tripId.equals(tripId))
          ..where((m) => m.status.equals('active')))
        .watch();
  }

  Stream<List<LocalExpense>> watchTripExpenses(String tripId) {
    return (select(localExpenses)
          ..where((e) => e.tripId.equals(tripId))
          ..orderBy([(e) => OrderingTerm.desc(e.spentAt)]))
        .watch();
  }

  Future<void> upsertTrip(LocalTripsCompanion trip) {
    return into(localTrips).insertOnConflictUpdate(trip);
  }

  Future<void> upsertMember(LocalTripMembersCompanion member) {
    return into(localTripMembers).insertOnConflictUpdate(member);
  }

  Future<void> upsertExpense(LocalExpensesCompanion expense) {
    return into(localExpenses).insertOnConflictUpdate(expense);
  }

  Future<void> upsertExpenseShare(LocalExpenseSharesCompanion share) {
    return into(localExpenseShares).insertOnConflictUpdate(share);
  }

  Future<void> deleteExpense(String expenseId) async {
    final expense = await (select(localExpenses)
          ..where((e) => e.id.equals(expenseId)))
        .getSingleOrNull();
    await _deleteLocalFileBestEffort(expense?.localReceiptPath);

    await (delete(localExpenseShares)
          ..where((s) => s.expenseId.equals(expenseId)))
        .go();
    await (delete(localExpenses)..where((e) => e.id.equals(expenseId))).go();
  }

  Stream<List<LocalSettlement>> watchTripSettlements(String tripId) {
    return (select(localSettlements)
          ..where((s) => s.tripId.equals(tripId))
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .watch();
  }

  Future<void> upsertSettlement(LocalSettlementsCompanion row) {
    return into(localSettlements).insertOnConflictUpdate(row);
  }

  Stream<List<LocalTripNote>> watchTripNotes(String tripId) {
    return (select(localTripNotes)
          ..where((n) => n.tripId.equals(tripId))
          ..orderBy([(n) => OrderingTerm.desc(n.capturedAt)]))
        .watch();
  }

  Stream<List<LocalTripPhoto>> watchTripPhotos(String tripId) {
    return (select(localTripPhotos)
          ..where((p) => p.tripId.equals(tripId))
          ..orderBy([(p) => OrderingTerm.desc(p.capturedAt)]))
        .watch();
  }

  Future<void> upsertTripNote(LocalTripNotesCompanion row) {
    return into(localTripNotes).insertOnConflictUpdate(row);
  }

  Future<void> upsertTripPhoto(LocalTripPhotosCompanion row) {
    return into(localTripPhotos).insertOnConflictUpdate(row);
  }

  Future<void> deleteTripNote(String id) {
    return (delete(localTripNotes)..where((n) => n.id.equals(id))).go();
  }

  /// Removes a trip and all dependent rows from the local cache.
  Future<void> deleteTripCascade(String tripId) async {
    final photos = await (select(localTripPhotos)
          ..where((p) => p.tripId.equals(tripId)))
        .get();
    for (final photo in photos) {
      await _deleteLocalFileBestEffort(photo.localPath);
    }

    final expenseIds = await (select(localExpenses)
          ..where((e) => e.tripId.equals(tripId)))
        .map((e) => e.id)
        .get();
    for (final expenseId in expenseIds) {
      await deleteExpense(expenseId);
    }
    await (delete(localSettlements)..where((s) => s.tripId.equals(tripId)))
        .go();
    await (delete(localTripNotes)..where((n) => n.tripId.equals(tripId))).go();
    await (delete(localTripPhotos)..where((p) => p.tripId.equals(tripId)))
        .go();
    await (delete(localTripMembers)..where((m) => m.tripId.equals(tripId)))
        .go();
    await (delete(localTrips)..where((t) => t.id.equals(tripId))).go();
  }

  Future<void> pruneExpensesForTrip(
    String tripId,
    Set<String> remoteExpenseIds, {
    Set<String> excludeIds = const {},
  }) async {
    final local = await (select(localExpenses)
          ..where((e) => e.tripId.equals(tripId)))
        .get();
    for (final row in local) {
      if (!remoteExpenseIds.contains(row.id) &&
          !excludeIds.contains(row.id)) {
        await deleteExpense(row.id);
      }
    }
  }

  Future<void> pruneSettlementsForTrip(
    String tripId,
    Set<String> remoteSettlementIds, {
    Set<String> excludeIds = const {},
  }) async {
    final local = await (select(localSettlements)
          ..where((s) => s.tripId.equals(tripId)))
        .get();
    for (final row in local) {
      if (!remoteSettlementIds.contains(row.id) &&
          !excludeIds.contains(row.id)) {
        await (delete(localSettlements)..where((s) => s.id.equals(row.id)))
            .go();
      }
    }
  }

  Future<void> _deleteLocalFileBestEffort(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

QueryExecutor _openConnection() => driftDatabase(
      name: 'vamo',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
