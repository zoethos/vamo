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
  LocalPlaces,
  LocalPlanItems,
  LocalTripListItems,
  LocalTripFxRates,
  LocalSyncOutbox,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory Drift for unit tests (persistence / query behavior).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2 && to >= 2) {
            await m.createTable(localExpenses);
            await m.createTable(localExpenseShares);
            await m.addColumn(
              localTripMembers,
              localTripMembers.displayName,
            );
          }
          if (from < 3 && to >= 3) {
            await m.createTable(localSettlements);
          }
          if (from < 4 && to >= 4) {
            await m.createTable(localTripNotes);
            await m.createTable(localTripPhotos);
          }
          if (from < 5 && to >= 5) {
            await m.createTable(localSyncOutbox);
          }
          if (from < 6 && to >= 6) {
            await m.addColumn(localExpenses, localExpenses.receiptPath);
            await m.addColumn(localExpenses, localExpenses.localReceiptPath);
            await m.addColumn(localExpenses, localExpenses.capturedLat);
            await m.addColumn(localExpenses, localExpenses.capturedLng);
            await m.addColumn(localExpenses, localExpenses.capturedAt);
          }
          if (from < 7 && to >= 7) {
            await m.addColumn(localExpenses, localExpenses.placeLabel);
          }
          if (from < 8 && to >= 8) {
            await m.createTable(localPlaces);
            await m.addColumn(localExpenses, localExpenses.placeId);
          }
          if (from < 9 && to >= 9) {
            await m.addColumn(localTrips, localTrips.lifecycle);
            await m.addColumn(localTrips, localTrips.closeRequestedAt);
            await m.addColumn(
              localTripMembers,
              localTripMembers.completedAt,
            );
            await m.addColumn(
              localTripMembers,
              localTripMembers.closeAcceptedAt,
            );
            await m.addColumn(
              localTripMembers,
              localTripMembers.closeObjectedAt,
            );
            await m.addColumn(
              localTripMembers,
              localTripMembers.closeObjectionReason,
            );
          }
          if (from < 10 && to >= 10) {
            await m.createTable(localPlanItems);
            await m.createTable(localTripListItems);
          }
          if (from < 11 && to >= 11) {
            await m.addColumn(localExpenses, localExpenses.status);
            await m.addColumn(localExpenseShares, localExpenseShares.response);
            await m.addColumn(
              localExpenseShares,
              localExpenseShares.responseReason,
            );
            await m.addColumn(
              localExpenseShares,
              localExpenseShares.respondedAt,
            );
          }
          if (from < 12 && to >= 12) {
            await m.addColumn(localTrips, localTrips.budgetMode);
            await m.addColumn(localTrips, localTrips.budgetCents);
            await m.createTable(localTripFxRates);
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

  Stream<LocalTripMember?> watchMember(String tripId, String userId) {
    return (select(localTripMembers)
          ..where((m) => m.tripId.equals(tripId))
          ..where((m) => m.userId.equals(userId)))
        .watchSingleOrNull();
  }

  Stream<List<LocalExpense>> watchTripExpenses(String tripId) {
    return (select(localExpenses)
          ..where((e) => e.tripId.equals(tripId))
          ..orderBy([(e) => OrderingTerm.desc(e.spentAt)]))
        .watch();
  }

  Stream<List<LocalExpense>> watchAllExpenses() {
    return (select(localExpenses)
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .watch();
  }

  Stream<List<LocalSettlement>> watchAllSettlements() {
    return (select(localSettlements)
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .watch();
  }

  Future<({int photos, int notes, int receipts})> countTripMedia(
    String tripId,
  ) async {
    final counts = await watchTripMediaCounts(tripId).first;
    return counts;
  }

  /// Live photo/note/receipt counts for trip cards (Drift watch).
  Stream<({int photos, int notes, int receipts})> watchTripMediaCounts(
    String tripId,
  ) {
    final photos$ = watchTripPhotos(tripId);
    final notes$ = watchTripNotes(tripId);
    final expenses$ = watchTripExpenses(tripId);

    return Stream.multi((controller) {
      var photos = 0;
      var notes = 0;
      var receipts = 0;

      void emit() {
        controller.add((photos: photos, notes: notes, receipts: receipts));
      }

      final subs = [
        photos$.listen((rows) {
          photos = rows.length;
          emit();
        }),
        notes$.listen((rows) {
          notes = rows.length;
          emit();
        }),
        expenses$.listen((rows) {
          receipts = rows
              .where(
                (e) =>
                    e.receiptPath != null ||
                    e.localReceiptPath != null,
              )
              .length;
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

  Stream<List<LocalPlace>> watchTripPlaces(String tripId) {
    return (select(localPlaces)
          ..where((p) => p.tripId.equals(tripId))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .watch();
  }

  Future<LocalPlace?> getPlace(String id) {
    return (select(localPlaces)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<LocalPlace>> listTripPlaces(String tripId) {
    return (select(localPlaces)..where((p) => p.tripId.equals(tripId))).get();
  }

  Future<void> upsertPlace(LocalPlacesCompanion row) {
    return into(localPlaces).insertOnConflictUpdate(row);
  }

  Future<void> upsertTrip(LocalTripsCompanion trip) {
    return into(localTrips).insertOnConflictUpdate(trip);
  }

  Stream<List<LocalTripFxRate>> watchTripFxRates(String tripId) {
    return (select(localTripFxRates)
          ..where((r) => r.tripId.equals(tripId))
          ..orderBy([(r) => OrderingTerm.asc(r.currency)]))
        .watch();
  }

  Future<void> upsertTripFxRate(LocalTripFxRatesCompanion row) {
    return into(localTripFxRates).insertOnConflictUpdate(row);
  }

  Future<void> pruneTripFxRates(String tripId, Set<String> remoteIds) async {
    final local = await (select(localTripFxRates)
          ..where((r) => r.tripId.equals(tripId)))
        .get();
    for (final row in local) {
      if (!remoteIds.contains(row.id)) {
        await (delete(localTripFxRates)..where((r) => r.id.equals(row.id)))
            .go();
      }
    }
  }

  Future<void> upsertMember(LocalTripMembersCompanion member) {
    return into(localTripMembers).insertOnConflictUpdate(member);
  }

  Future<void> upsertExpense(LocalExpensesCompanion expense) {
    return into(localExpenses).insertOnConflictUpdate(expense);
  }

  Stream<List<LocalExpenseShare>> watchTripExpenseShares(String tripId) {
    return (select(localExpenseShares)
          ..where(
            (s) => s.expenseId.isInQuery(
              selectOnly(localExpenses)
                ..addColumns([localExpenses.id])
                ..where(localExpenses.tripId.equals(tripId)),
            ),
          ))
        .watch();
  }

  Future<void> upsertExpenseShare(LocalExpenseSharesCompanion share) async {
    assert(share.id.present, 'upsertExpenseShare requires id');
    final id = share.id.value;
    final updated =
        await (update(localExpenseShares)..where((s) => s.id.equals(id)))
            .write(share);
    if (updated == 0) {
      await into(localExpenseShares).insertOnConflictUpdate(share);
    }
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

  Stream<List<LocalPlanItem>> watchTripPlanItems(String tripId) {
    return (select(localPlanItems)
          ..where((p) => p.tripId.equals(tripId))
          ..orderBy([
            (p) => OrderingTerm.asc(p.startsAt),
            (p) => OrderingTerm.asc(p.position),
          ]))
        .watch();
  }

  Stream<List<LocalTripListItem>> watchTripListItems(String tripId) {
    return (select(localTripListItems)
          ..where((l) => l.tripId.equals(tripId))
          ..orderBy([
            (l) => OrderingTerm.asc(l.listName),
            (l) => OrderingTerm.asc(l.position),
          ]))
        .watch();
  }

  Future<void> upsertPlanItem(LocalPlanItemsCompanion row) async {
    assert(row.id.present, 'upsertPlanItem requires id');
    final id = row.id.value;
    final updated =
        await (update(localPlanItems)..where((p) => p.id.equals(id))).write(row);
    if (updated == 0) {
      await into(localPlanItems).insertOnConflictUpdate(row);
    }
  }

  Future<void> upsertListItem(LocalTripListItemsCompanion row) async {
    assert(row.id.present, 'upsertListItem requires id');
    final id = row.id.value;
    final updated =
        await (update(localTripListItems)..where((l) => l.id.equals(id)))
            .write(row);
    if (updated == 0) {
      await into(localTripListItems).insertOnConflictUpdate(row);
    }
  }

  Future<void> deletePlanItem(String id) {
    return (delete(localPlanItems)..where((p) => p.id.equals(id))).go();
  }

  Future<void> deleteListItem(String id) {
    return (delete(localTripListItems)..where((l) => l.id.equals(id))).go();
  }

  Future<void> prunePlanItemsForTrip(
    String tripId,
    Set<String> remoteIds, {
    Set<String> excludeIds = const {},
  }) async {
    final local = await (select(localPlanItems)
          ..where((p) => p.tripId.equals(tripId)))
        .get();
    for (final row in local) {
      if (!remoteIds.contains(row.id) && !excludeIds.contains(row.id)) {
        await deletePlanItem(row.id);
      }
    }
  }

  Future<void> pruneListItemsForTrip(
    String tripId,
    Set<String> remoteIds, {
    Set<String> excludeIds = const {},
  }) async {
    final local = await (select(localTripListItems)
          ..where((l) => l.tripId.equals(tripId)))
        .get();
    for (final row in local) {
      if (!remoteIds.contains(row.id) && !excludeIds.contains(row.id)) {
        await deleteListItem(row.id);
      }
    }
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
    await (delete(localPlaces)..where((p) => p.tripId.equals(tripId))).go();
    await (delete(localPlanItems)..where((p) => p.tripId.equals(tripId))).go();
    await (delete(localTripListItems)..where((l) => l.tripId.equals(tripId)))
        .go();
    await (delete(localTripFxRates)..where((r) => r.tripId.equals(tripId))).go();
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
