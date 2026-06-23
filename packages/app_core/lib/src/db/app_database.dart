import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../analytics/action_failure.dart';
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
  LocalTripVideos,
  LocalPlaces,
  LocalPlanItems,
  LocalTripListItems,
  LocalTripFxRates,
  LocalPlanItemRsvps,
  LocalSyncOutbox,
  LocalNotifications,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory Drift for unit tests (persistence / query behavior).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 23;

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
          if (from < 13 && to >= 13) {
            await m.createTable(localPlanItemRsvps);
          }
          if (from < 14 && to >= 14) {
            await m.addColumn(localTrips, localTrips.backgroundPath);
            await m.addColumn(localTrips, localTrips.backgroundLocalPath);
          }
          if (from < 15 && to >= 15) {
            await m.addColumn(
              localTripMembers,
              localTripMembers.closeNotifiedAt,
            );
            await m.addColumn(
              localTripMembers,
              localTripMembers.closeRemindedAt,
            );
            await m.addColumn(
              localTripMembers,
              localTripMembers.settleNudgedAt,
            );
          }
          if (from < 16 && to >= 16) {
            await m.createTable(localNotifications);
          }
          if (from < 17 && to >= 17) {
            await m.createTable(localTripVideos);
          }
          if (from < 18 && to >= 18) {
            await m.addColumn(localTripPhotos, localTripPhotos.capturedLat);
            await m.addColumn(localTripPhotos, localTripPhotos.capturedLng);
            await m.addColumn(
              localTripPhotos,
              localTripPhotos.mediaCapturedAt,
            );
          }
          if (from < 19 && to >= 19) {
            await m.addColumn(
              localTripMembers,
              localTripMembers.avatarUrl,
            );
          }
          if (from < 20 && to >= 20) {
            await m.addColumn(localPlanItems, localPlanItems.metadata);
          }
          if (from < 21 && to >= 21) {
            await m.addColumn(localExpenses, localExpenses.fxRateSource);
            await m.addColumn(localExpenses, localExpenses.fxRateManual);
            await m.addColumn(localExpenses, localExpenses.fxConversionLocked);
          }
          if (from < 22 && to >= 22) {
            await m.addColumn(
              localTripMembers,
              localTripMembers.avatarDisplayMode,
            );
            await m.addColumn(
              localTripMembers,
              localTripMembers.avatarInitials,
            );
          }
          if (from < 23 && to >= 23) {
            await m.addColumn(localTripMembers, localTripMembers.joinedAt);
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
                (e) => e.receiptPath != null || e.localReceiptPath != null,
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

  /// Partial-safe update of an existing trip row (no insert path, so a partial
  /// companion can't fail Drift insert-integrity validation). Returns rows affected.
  Future<int> updateTripFields(String tripId, LocalTripsCompanion fields) {
    return (update(localTrips)..where((t) => t.id.equals(tripId)))
        .write(fields);
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

  Future<int> updateExpenseFields(
    String expenseId,
    LocalExpensesCompanion fields,
  ) {
    return (update(localExpenses)..where((e) => e.id.equals(expenseId)))
        .write(fields);
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
    final updated = await (update(localExpenseShares)
          ..where((s) => s.id.equals(id)))
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

  Stream<List<LocalTripVideo>> watchTripVideos(String tripId) {
    return (select(localTripVideos)
          ..where((v) => v.tripId.equals(tripId))
          ..orderBy([(v) => OrderingTerm.desc(v.capturedAt)]))
        .watch();
  }

  Future<void> upsertTripNote(LocalTripNotesCompanion row) {
    return into(localTripNotes).insertOnConflictUpdate(row);
  }

  Future<void> upsertTripPhoto(LocalTripPhotosCompanion row) {
    return into(localTripPhotos).insertOnConflictUpdate(row);
  }

  Future<int> updateTripPhotoFields(
    String photoId,
    LocalTripPhotosCompanion fields,
  ) {
    return (update(localTripPhotos)..where((p) => p.id.equals(photoId)))
        .write(fields);
  }

  Future<void> upsertTripVideo(LocalTripVideosCompanion row) {
    return into(localTripVideos).insertOnConflictUpdate(row);
  }

  Future<int> updateTripVideoFields(
    String videoId,
    LocalTripVideosCompanion fields,
  ) {
    return (update(localTripVideos)..where((v) => v.id.equals(videoId)))
        .write(fields);
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
    final updated = await (update(localPlanItems)
          ..where((p) => p.id.equals(id)))
        .write(row);
    if (updated == 0) {
      await into(localPlanItems).insertOnConflictUpdate(row);
    }
  }

  Future<void> upsertListItem(LocalTripListItemsCompanion row) async {
    assert(row.id.present, 'upsertListItem requires id');
    final id = row.id.value;
    final updated = await (update(localTripListItems)
          ..where((l) => l.id.equals(id)))
        .write(row);
    if (updated == 0) {
      await into(localTripListItems).insertOnConflictUpdate(row);
    }
  }

  Future<void> deletePlanItem(String id) async {
    await (delete(localPlanItemRsvps)..where((r) => r.planItemId.equals(id)))
        .go();
    await (delete(localPlanItems)..where((p) => p.id.equals(id))).go();
  }

  Stream<List<LocalPlanItemRsvp>> watchTripPlanItemRsvps(String tripId) {
    return (select(localPlanItemRsvps)
          ..where(
            (r) => r.planItemId.isInQuery(
              selectOnly(localPlanItems)
                ..addColumns([localPlanItems.id])
                ..where(localPlanItems.tripId.equals(tripId)),
            ),
          )
          ..orderBy([(r) => OrderingTerm.desc(r.respondedAt)]))
        .watch();
  }

  Future<void> upsertPlanItemRsvp(LocalPlanItemRsvpsCompanion row) {
    return into(localPlanItemRsvps).insertOnConflictUpdate(row);
  }

  Stream<List<LocalNotification>> watchNotifications(String userId) {
    return (select(localNotifications)
          ..where((n) => n.userId.equals(userId))
          ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
        .watch();
  }

  Stream<int> watchUnreadNotificationCount(String userId) {
    return (select(localNotifications)
          ..where((n) => n.userId.equals(userId))
          ..where((n) => n.readAt.isNull()))
        .watch()
        .map((rows) => rows.length);
  }

  Future<void> upsertNotification(LocalNotificationsCompanion row) {
    return into(localNotifications).insertOnConflictUpdate(row);
  }

  Future<void> markNotificationReadLocal(String id) async {
    await (update(localNotifications)..where((n) => n.id.equals(id))).write(
      LocalNotificationsCompanion(
        readAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> markAllNotificationsReadLocal(String userId) async {
    await (update(localNotifications)
          ..where((n) => n.userId.equals(userId))
          ..where((n) => n.readAt.isNull()))
        .write(
      LocalNotificationsCompanion(
        readAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> pruneNotifications(Set<String> remoteIds) async {
    final local = await select(localNotifications).get();
    for (final row in local) {
      if (!remoteIds.contains(row.id)) {
        await (delete(localNotifications)..where((n) => n.id.equals(row.id)))
            .go();
      }
    }
  }

  Future<void> prunePlanItemRsvpsForTrip(
    String tripId,
    Set<String> remoteIds,
  ) async {
    final local = await (select(localPlanItemRsvps)
          ..where(
            (r) => r.planItemId.isInQuery(
              selectOnly(localPlanItems)
                ..addColumns([localPlanItems.id])
                ..where(localPlanItems.tripId.equals(tripId)),
            ),
          ))
        .get();
    for (final row in local) {
      if (!remoteIds.contains(row.id)) {
        await (delete(localPlanItemRsvps)..where((r) => r.id.equals(row.id)))
            .go();
      }
    }
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
    final videos = await (select(localTripVideos)
          ..where((v) => v.tripId.equals(tripId)))
        .get();
    for (final video in videos) {
      await _deleteLocalFileBestEffort(video.localPath);
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
    await (delete(localTripPhotos)..where((p) => p.tripId.equals(tripId))).go();
    await (delete(localTripVideos)..where((v) => v.tripId.equals(tripId))).go();
    await (delete(localPlaces)..where((p) => p.tripId.equals(tripId))).go();
    await (delete(localPlanItems)..where((p) => p.tripId.equals(tripId))).go();
    await (delete(localPlanItemRsvps)
          ..where(
            (r) => r.planItemId.isInQuery(
              selectOnly(localPlanItems)
                ..addColumns([localPlanItems.id])
                ..where(localPlanItems.tripId.equals(tripId)),
            ),
          ))
        .go();
    await (delete(localTripListItems)..where((l) => l.tripId.equals(tripId)))
        .go();
    await (delete(localTripFxRates)..where((r) => r.tripId.equals(tripId)))
        .go();
    await (delete(localNotifications)..where((n) => n.tripId.equals(tripId)))
        .go();
    await (delete(localTripMembers)..where((m) => m.tripId.equals(tripId)))
        .go();
    await (delete(localTrips)..where((t) => t.id.equals(tripId))).go();
  }

  /// Drops local media cache for rows that are already backed by remote storage.
  /// Local-only/offline media is intentionally left untouched.
  Future<({int backgrounds, int photos, int videos, int receipts})>
      offloadTripMediaCache(String tripId) async {
    var backgrounds = 0;
    var photos = 0;
    var videos = 0;
    var receipts = 0;

    final trip = await (select(localTrips)..where((t) => t.id.equals(tripId)))
        .getSingleOrNull();
    if (_hasValue(trip?.backgroundPath) &&
        _hasValue(trip?.backgroundLocalPath)) {
      await _deleteLocalFileBestEffort(trip!.backgroundLocalPath);
      await updateTripFields(
        tripId,
        const LocalTripsCompanion(backgroundLocalPath: Value(null)),
      );
      backgrounds++;
    }

    final photoRows = await (select(localTripPhotos)
          ..where((p) => p.tripId.equals(tripId)))
        .get();
    for (final photo in photoRows) {
      if (!_hasValue(photo.storagePath) || !_hasValue(photo.localPath)) {
        continue;
      }
      await _deleteLocalFileBestEffort(photo.localPath);
      await updateTripPhotoFields(
        photo.id,
        const LocalTripPhotosCompanion(localPath: Value(null)),
      );
      photos++;
    }

    final videoRows = await (select(localTripVideos)
          ..where((v) => v.tripId.equals(tripId)))
        .get();
    for (final video in videoRows) {
      if (!_hasValue(video.storagePath) || !_hasValue(video.localPath)) {
        continue;
      }
      await _deleteLocalFileBestEffort(video.localPath);
      await updateTripVideoFields(
        video.id,
        const LocalTripVideosCompanion(localPath: Value(null)),
      );
      videos++;
    }

    final expenseRows = await (select(localExpenses)
          ..where((e) => e.tripId.equals(tripId)))
        .get();
    for (final expense in expenseRows) {
      if (!_hasValue(expense.receiptPath) ||
          !_hasValue(expense.localReceiptPath)) {
        continue;
      }
      await _deleteLocalFileBestEffort(expense.localReceiptPath);
      await updateExpenseFields(
        expense.id,
        const LocalExpensesCompanion(localReceiptPath: Value(null)),
      );
      receipts++;
    }

    return (
      backgrounds: backgrounds,
      photos: photos,
      videos: videos,
      receipts: receipts,
    );
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
      if (!remoteExpenseIds.contains(row.id) && !excludeIds.contains(row.id)) {
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
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'db',
        action: 'delete_local_file',
        severity: ActionFailureSeverity.degraded,
      );
    }
  }

  bool _hasValue(String? value) => value != null && value.isNotEmpty;
}

QueryExecutor _openConnection() => driftDatabase(
      name: 'vamo',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
