import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncQueue queue;
  late DateTime now;
  late TripOfflinePackService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueue(db);
    now = DateTime.utc(2026, 6, 25, 10);
    service = TripOfflinePackService(
      db: db,
      syncQueue: queue,
      now: () => now,
    );
  });

  tearDown(() => db.close());

  test('refreshEssentials persists a ready manifest from local rows', () async {
    await _seedTripEssentials(db, now: now);

    final manifest = await service.refreshEssentials('trip-1');

    expect(manifest.status, OfflinePackStatus.ready);
    expect(manifest.rowCounts.trips, 1);
    expect(manifest.rowCounts.members, 1);
    expect(manifest.rowCounts.planItems, 1);
    expect(manifest.rowCounts.checklists, 1);
    expect(manifest.rowCounts.rsvps, 1);
    expect(manifest.rowCounts.places, 1);
    expect(manifest.rowCounts.fxRates, 1);
    expect(manifest.rowCounts.expenses, 1);
    expect(manifest.rowCounts.expenseShares, 1);
    expect(manifest.rowCounts.settlements, 1);

    final stored = await service.getEssentialsManifest('trip-1');
    expect(stored?.status, OfflinePackStatus.ready);
    expect(stored?.lastUpdatedLabel(now: now), 'Last updated: just now');
  });

  test('refreshEssentials records cache miss as failed without projection blob',
      () async {
    final manifest = await service.refreshEssentials('missing-trip');

    expect(manifest.status, OfflinePackStatus.failed);
    expect(manifest.missingScopes, contains(OfflinePackScope.trip));
    expect(manifest.rowCounts.totalRows, 0);
    expect(manifest.secureSnapshotRef, isNull);

    final stored = await db.getOfflinePack(
      'missing-trip',
      OfflinePackTier.essentials.value,
    );
    expect(stored?.rowCountsJson, contains('"trips":0'));
  });

  test('pending outbox surfaces partial status and never blocks pack refresh',
      () async {
    await _seedTripEssentials(db, now: now);
    await queue.enqueue(
      kind: SyncKind.planItemUpsert,
      payload: {'id': 'plan-pending', 'trip_id': 'trip-1'},
    );

    final manifest = await service.refreshEssentials('trip-1');

    expect(manifest.status, OfflinePackStatus.partial);
    expect(manifest.pendingOutboxCount, 1);
    expect(manifest.staleReasons, contains('pending_outbox'));
    expect(manifest.isUsableOffline, isTrue);
  });

  test('policy surfaces stale state and Last updated text', () {
    final policy = const OfflinePackPolicy(staleAfter: Duration(hours: 12));
    final manifest = policy.surfaceStaleness(
      manifest: OfflinePackManifest(
        tripId: 'trip-1',
        tier: OfflinePackTier.essentials,
        status: OfflinePackStatus.ready,
        lastUpdatedAt: now.subtract(const Duration(days: 2)),
        rowCounts: const OfflinePackRowCounts(trips: 1, members: 1),
      ),
      now: now,
    );

    expect(manifest.status, OfflinePackStatus.stale);
    expect(manifest.staleReasons, contains('last_updated_age'));
    expect(manifest.lastUpdatedLabel(now: now), 'Last updated: 2d ago');
  });

  test('eviction honors cap while protecting pinned and pending packs', () {
    final policy = const OfflinePackPolicy();
    final plan = policy.planEviction(
      maxWarmPacks: 1,
      now: now,
      candidates: [
        _candidate('archived', lifecycle: 'archived'),
        _candidate('old-active', accessedDaysAgo: 8),
        _candidate('fresh-active', accessedDaysAgo: 1),
        _candidate('pinned', accessedDaysAgo: 20, evictionPinned: true),
        _candidate('pending', accessedDaysAgo: 30, pendingOutboxCount: 1),
      ],
    );

    expect(plan.evictTripIds, contains('archived'));
    expect(plan.evictTripIds, contains('old-active'));
    expect(plan.evictTripIds, isNot(contains('fresh-active')));
    expect(plan.evictTripIds, isNot(contains('pinned')));
    expect(plan.evictTripIds, isNot(contains('pending')));
  });

  test('map snapshot policy never bulk-prefetches OSM tiles', () {
    final plan = const OfflinePackPolicy().mapSnapshotPlan(provider: 'osm');

    expect(plan.pinsOnly, isTrue);
    expect(plan.bulkTilePrefetch, isFalse);
    expect(plan.tileDownloadRequests, 0);
    expect(plan.licenseGuard, 'pins_list_only_no_bulk_tile_prefetch');
  });

  test('secure storage adapter stores only reusable key material', () async {
    final store = MemoryOfflinePackKeyStore();

    final first = await store.getOrCreateKey(tripId: 'trip-1');
    final second = await store.getOrCreateKey(tripId: 'trip-1');

    expect(first, second);
    expect(first.length, lessThan(80));
  });

  test('refreshDueLocalEssentials skips fresh foreground packs', () async {
    await _seedTripEssentials(db, now: now);
    await service.refreshEssentials('trip-1');

    now = now.add(const Duration(hours: 1));
    await service.refreshDueLocalEssentials(
      trigger: OfflinePackRefreshTrigger.appForeground,
    );

    final stored = await service.getEssentialsManifest('trip-1');
    expect(stored?.lastUpdatedAt, DateTime.utc(2026, 6, 25, 10));
  });

  test('refreshDueLocalEssentials refreshes pre-departure packs', () async {
    await _seedTripEssentials(db, now: now);
    await service.refreshEssentials('trip-1');

    now = DateTime.utc(2026, 6, 30, 12);
    await service.refreshDueLocalEssentials(
      trigger: OfflinePackRefreshTrigger.preDeparture,
    );

    final stored = await service.getEssentialsManifest('trip-1');
    expect(stored?.lastUpdatedAt, DateTime.utc(2026, 6, 30, 12));
  });
}

OfflinePackEvictionCandidate _candidate(
  String tripId, {
  int accessedDaysAgo = 0,
  String lifecycle = 'active',
  bool evictionPinned = false,
  int pendingOutboxCount = 0,
}) {
  final now = DateTime.utc(2026, 6, 25, 10);
  return OfflinePackEvictionCandidate(
    tripId: tripId,
    tier: OfflinePackTier.essentials,
    status: OfflinePackStatus.ready,
    lastAccessedAt: now.subtract(Duration(days: accessedDaysAgo)),
    tripEndDate:
        lifecycle == 'archived' ? now.subtract(const Duration(days: 1)) : null,
    lifecycle: lifecycle,
    evictionPinned: evictionPinned,
    pendingOutboxCount: pendingOutboxCount,
  );
}

Future<void> _seedTripEssentials(
  AppDatabase db, {
  required DateTime now,
}) async {
  await db.upsertTrip(
    LocalTripsCompanion(
      id: const Value('trip-1'),
      name: const Value('Rome'),
      destination: const Value('Pantheon'),
      ownerId: const Value('user-1'),
      baseCurrency: const Value('EUR'),
      startDate: const Value('2026-07-01'),
      endDate: const Value('2026-07-05'),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );
  await db.upsertMember(
    LocalTripMembersCompanion(
      tripId: const Value('trip-1'),
      userId: const Value('user-1'),
      role: const Value('owner'),
      status: const Value('active'),
      displayName: const Value('Ari'),
      joinedAt: Value(now),
    ),
  );
  await db.upsertPlanItem(
    LocalPlanItemsCompanion(
      id: const Value('plan-1'),
      tripId: const Value('trip-1'),
      kind: const Value('visit'),
      title: const Value('Pantheon'),
      metadata:
          const Value('{"place_label":"Pantheon","lat":41.8986,"lng":12.4769}'),
      position: const Value(0),
      createdBy: const Value('user-1'),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );
  await db.upsertListItem(
    LocalTripListItemsCompanion(
      id: const Value('list-1'),
      tripId: const Value('trip-1'),
      listName: const Value('Packing'),
      label: const Value('Passport'),
      createdBy: const Value('user-1'),
      createdAt: Value(now),
    ),
  );
  await db.upsertPlanItemRsvp(
    LocalPlanItemRsvpsCompanion(
      id: const Value('rsvp-1'),
      planItemId: const Value('plan-1'),
      userId: const Value('user-1'),
      status: const Value('going'),
      respondedAt: Value(now),
    ),
  );
  await db.upsertPlace(
    LocalPlacesCompanion(
      id: const Value('place-1'),
      tripId: const Value('trip-1'),
      label: const Value('Pantheon'),
      lat: const Value(41.8986),
      lng: const Value(12.4769),
      source: const Value('confirmed_canonical_projection'),
      confidence: const Value(0.9),
      createdBy: const Value('user-1'),
      createdAt: Value(now),
    ),
  );
  await db.upsertTripFxRate(
    LocalTripFxRatesCompanion(
      id: const Value('fx-1'),
      tripId: const Value('trip-1'),
      currency: const Value('USD'),
      rate: const Value(0.92),
      source: const Value('snapshot'),
      capturedAt: Value(now),
      capturedBy: const Value('user-1'),
    ),
  );
  await db.upsertExpense(
    LocalExpensesCompanion(
      id: const Value('expense-1'),
      tripId: const Value('trip-1'),
      payerId: const Value('user-1'),
      amountCents: const Value(1200),
      currency: const Value('EUR'),
      baseCents: const Value(1200),
      fxRate: const Value(1),
      description: const Value('Tickets'),
      spentAt: Value(now),
      createdBy: const Value('user-1'),
      createdAt: Value(now),
      placeId: const Value('place-1'),
      placeLabel: const Value('Pantheon'),
    ),
  );
  await db.upsertExpenseShare(
    LocalExpenseSharesCompanion(
      id: const Value('share-1'),
      expenseId: const Value('expense-1'),
      userId: const Value('user-1'),
      shareCents: const Value(1200),
    ),
  );
  await db.upsertSettlement(
    LocalSettlementsCompanion(
      id: const Value('settlement-1'),
      tripId: const Value('trip-1'),
      fromUser: const Value('user-1'),
      toUser: const Value('user-2'),
      amountCents: const Value(500),
      currency: const Value('EUR'),
      status: const Value('marked'),
      createdAt: Value(now),
    ),
  );
}
