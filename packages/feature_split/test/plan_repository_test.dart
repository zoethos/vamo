import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:feature_split/src/plan/event_rsvp_models.dart';
import 'package:feature_split/src/plan/plan_models.dart';
import 'package:feature_split/src/plan/plan_repository.dart';
import 'package:feature_split/src/places/places_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('groupPlanItemsByDay puts undated items last', () {
    final items = [
      PlanItemSummary(
        id: '1',
        tripId: 't',
        kind: PlanItemKind.other,
        title: 'Undated',
        position: 0,
      ),
      PlanItemSummary(
        id: '2',
        tripId: 't',
        kind: PlanItemKind.flight,
        title: 'Day 1',
        startsAt: DateTime.utc(2026, 7, 1, 14),
        position: 1,
      ),
      PlanItemSummary(
        id: '3',
        tripId: 't',
        kind: PlanItemKind.lodging,
        title: 'Day 2',
        startsAt: DateTime.utc(2026, 7, 2, 9),
        position: 2,
      ),
    ];

    final grouped = groupPlanItemsByDay(items);
    expect(grouped, hasLength(3));
    expect(grouped.first.dayKey, '2026-07-01');
    expect(grouped.last.dayKey, isNull);
    expect(grouped.last.items.single.title, 'Undated');
  });

  test('groupPlanItemsBySubtrip keeps main and subtrip sections separate', () {
    final subtrip = SubtripSummary(
      id: 'sub-1',
      tripId: 't',
      name: 'Tokyo crew',
      createdBy: 'u1',
      createdAt: DateTime.utc(2026, 6, 1),
      memberIds: const ['u1', 'u2'],
    );
    final grouped = groupPlanItemsBySubtrip(
      subtrips: [subtrip],
      items: [
        const PlanItemSummary(
          id: 'main',
          tripId: 't',
          kind: PlanItemKind.other,
          title: 'Everyone dinner',
          position: 0,
        ),
        const PlanItemSummary(
          id: 'sub',
          tripId: 't',
          subtripId: 'sub-1',
          kind: PlanItemKind.visit,
          title: 'Ghibli Museum',
          position: 1,
        ),
      ],
    );

    expect(grouped, hasLength(2));
    expect(grouped.first.subtrip, isNull);
    expect(grouped.first.daySections.single.items.single.id, 'main');
    expect(grouped.last.subtrip?.name, 'Tokyo crew');
    expect(grouped.last.daySections.single.items.single.id, 'sub');
  });

  test('plan metadata helpers preserve objects and reject invalid shapes', () {
    expect(parsePlanMetadata(null), isEmpty);
    expect(parsePlanMetadata(''), isEmpty);
    expect(parsePlanMetadata('not json'), isEmpty);
    expect(parsePlanMetadata('[1,2]'), isEmpty);
    expect(
      parsePlanMetadata('{"gate":"A12","nested":{"z":1}}'),
      {
        'gate': 'A12',
        'nested': {'z': 1}
      },
    );
    expect(
      encodePlanMetadata({
        'z': 1,
        'a': true,
      }),
      '{"a":true,"z":1}',
    );
  });

  test('visit metadata helpers normalize place fields', () {
    final metadata = buildVisitPlaceMetadata(
      placeLabel: '  Amalfi Cathedral  ',
      address: '  Piazza Duomo, Amalfi  ',
      lat: 40.634,
      lng: 14.602,
      placeId: '  place-1  ',
    );

    expect(metadata, {
      'place_label': 'Amalfi Cathedral',
      'address': 'Piazza Duomo, Amalfi',
      'lat': 40.634,
      'lng': 14.602,
      'place_id': 'place-1',
    });

    final visit = parseVisitPlaceMetadata(metadata);
    expect(visit?.placeLabel, 'Amalfi Cathedral');
    expect(visit?.address, 'Piazza Duomo, Amalfi');
    expect(visit?.lat, 40.634);
    expect(visit?.lng, 14.602);
    expect(visit?.placeId, 'place-1');
    expect(visit?.hasCoords, isTrue);

    final stringCoords = parseVisitPlaceMetadata({
      'place_label': 'Pompei',
      'lat': '40.748',
      'lng': '14.485',
    });
    expect(stringCoords?.lat, 40.748);
    expect(stringCoords?.lng, 14.485);
    expect(parseVisitPlaceMetadata({'address': 'No label'}), isNull);
  });

  test('capability fallback keeps activity RSVP behavior', () {
    final fallback = PlanItemCapabilities.fallbackByKind();
    expect(PlanItemKind.parse('visit'), PlanItemKind.visit);
    expect(fallback[PlanItemKind.activity]?.supportsRsvp, isTrue);
    expect(fallback[PlanItemKind.activity]?.suggestsPois, isTrue);
    expect(fallback[PlanItemKind.visit]?.supportsRsvp, isFalse);
    expect(fallback[PlanItemKind.visit]?.suggestsPois, isTrue);
    expect(fallback[PlanItemKind.visit]?.hasDetailsForm, isTrue);
    expect(PlanItemKind.parse('transfer'), PlanItemKind.transfer);
    expect(fallback[PlanItemKind.transfer]?.hasLiveStatus, isTrue);
    expect(fallback[PlanItemKind.transfer]?.hasCheckTimes, isTrue);
    expect(fallback[PlanItemKind.transfer]?.hasDetailsForm, isTrue);
    expect(fallback[PlanItemKind.transfer]?.suggestsPois, isFalse);
    expect(fallback[PlanItemKind.flight]?.hasLiveStatus, isTrue);
    expect(fallback[PlanItemKind.train]?.hasLiveStatus, isTrue);
    expect(fallback[PlanItemKind.other]?.supportsRsvp, isFalse);
  });

  test('places repository streams trip-scoped place summaries', () async {
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final repo = PlacesRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      syncQueue: SyncQueue(db),
    );
    final now = DateTime.utc(2026, 6, 20);

    await db.upsertPlace(
      LocalPlacesCompanion(
        id: const Value('place-1'),
        tripId: const Value('trip-plan'),
        label: const Value('Amalfi Cathedral'),
        address: const Value('Piazza Duomo'),
        lat: const Value(40.634),
        lng: const Value(14.602),
        source: const Value('receipt'),
        confidence: const Value(0.8),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
      ),
    );

    final places = await repo.watchTripPlaces('trip-plan').first;
    expect(places, hasLength(1));
    expect(places.single.label, 'Amalfi Cathedral');
    expect(places.single.address, 'Piazza Duomo');
  });

  test('addPlanItem preserves metadata locally and in outbox', () async {
    const tripId = 'trip-plan';
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final worker = SyncWorker(
      queue: queue,
      client: client,
      analytics: DebugAnalytics(),
    );
    final repo = PlanRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      syncQueue: queue,
      syncWorker: worker,
      currentUserIdOverride: 'user-1',
    );

    await repo.addPlanItem(
      const PlanItemInput(
        tripId: tripId,
        kind: PlanItemKind.flight,
        title: 'Flight',
        metadata: {'flight_number': 'AZ123'},
      ),
    );

    final rows = await repo.watchPlanItems(tripId).first;
    expect(rows.single.metadata, {'flight_number': 'AZ123'});

    final pending = await queue.pending();
    final payload = decodePayload(pending.single.payload);
    expect(payload['metadata'], {'flight_number': 'AZ123'});
  });

  test('addPlanItem preserves subtrip id locally and in outbox', () async {
    const tripId = 'trip-plan';
    const subtripId = 'subtrip-plan';
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final worker = SyncWorker(
      queue: queue,
      client: client,
      analytics: DebugAnalytics(),
    );
    final repo = PlanRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      syncQueue: queue,
      syncWorker: worker,
      currentUserIdOverride: 'user-1',
    );

    await repo.addPlanItem(
      const PlanItemInput(
        tripId: tripId,
        subtripId: subtripId,
        kind: PlanItemKind.visit,
        title: 'Ghibli Museum',
      ),
    );

    final rows = await repo.watchPlanItems(tripId).first;
    expect(rows.single.subtripId, subtripId);

    final pending = await queue.pending();
    final payload = decodePayload(pending.single.payload);
    expect(payload['subtrip_id'], subtripId);
  });

  test('addPlanItem preserves transfer metadata locally and in outbox',
      () async {
    const tripId = 'trip-plan';
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final worker = SyncWorker(
      queue: queue,
      client: client,
      analytics: DebugAnalytics(),
    );
    final repo = PlanRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      syncQueue: queue,
      syncWorker: worker,
      currentUserIdOverride: 'user-1',
    );
    final metadata = buildTransferMetadata(
      subtype: TransferSubtype.train,
      origin: 'Roma Termini',
      destination: 'Napoli Centrale',
      provider: 'Italo',
      reference: '8921',
    );

    await repo.addPlanItem(
      PlanItemInput(
        tripId: tripId,
        kind: PlanItemKind.transfer,
        title: 'Train to Naples',
        metadata: metadata,
      ),
    );

    final rows = await repo.watchPlanItems(tripId).first;
    expect(rows.single.kind, PlanItemKind.transfer);
    expect(rows.single.metadata, metadata);
    expect(parseTransferMetadata(rows.single.metadata)?.subtype,
        TransferSubtype.train);

    final pending = await queue.pending();
    final payload = decodePayload(pending.single.payload);
    expect(payload['kind'], 'transfer');
    expect(payload['metadata'], metadata);
  });

  test('plan item reorder swaps positions in drift', () async {
    const tripId = 'trip-plan';
    final now = DateTime.utc(2026, 6, 5);

    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('a'),
        tripId: const Value(tripId),
        kind: const Value('lodging'),
        title: const Value('A'),
        position: const Value(0),
        createdBy: const Value('u1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('b'),
        tripId: const Value(tripId),
        kind: const Value('train'),
        title: const Value('B'),
        position: const Value(1),
        createdBy: const Value('u1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await db.upsertPlanItem(
      const LocalPlanItemsCompanion(
        id: Value('a'),
        position: Value(1),
      ),
    );
    await db.upsertPlanItem(
      const LocalPlanItemsCompanion(
        id: Value('b'),
        position: Value(0),
      ),
    );

    final rows = await db.watchTripPlanItems(tripId).first;
    expect(rows.firstWhere((r) => r.id == 'a').position, 1);
    expect(rows.firstWhere((r) => r.id == 'b').position, 0);
  });

  test('reorder preserves metadata in queued plan upserts', () async {
    const tripId = 'trip-plan';
    final now = DateTime.utc(2026, 6, 5);

    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('a'),
        tripId: const Value(tripId),
        kind: const Value('lodging'),
        title: const Value('A'),
        metadata: const Value('{"booking":"ABC"}'),
        position: const Value(0),
        createdBy: const Value('u1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('b'),
        tripId: const Value(tripId),
        kind: const Value('train'),
        title: const Value('B'),
        metadata: const Value('{"line":"IC"}'),
        position: const Value(1),
        createdBy: const Value('u1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final worker = SyncWorker(
      queue: queue,
      client: client,
      analytics: DebugAnalytics(),
    );
    final repo = PlanRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      syncQueue: queue,
      syncWorker: worker,
      currentUserIdOverride: 'user-1',
    );

    await repo.reorderPlanItem(tripId: tripId, itemId: 'a', newPosition: 1);

    final payloads = (await queue.pending())
        .map((row) => decodePayload(row.payload))
        .toList();
    expect(payloads, hasLength(2));
    expect(
      payloads.singleWhere((payload) => payload['id'] == 'a')['metadata'],
      {'booking': 'ABC'},
    );
    expect(
      payloads.singleWhere((payload) => payload['id'] == 'b')['metadata'],
      {'line': 'IC'},
    );
  });

  test('checklist toggle round-trip in drift', () async {
    const tripId = 'trip-plan';
    const userId = 'user-plan';
    final now = DateTime.utc(2026, 6, 5);

    await db.upsertListItem(
      LocalTripListItemsCompanion(
        id: const Value('list-1'),
        tripId: const Value(tripId),
        listName: const Value('Packing'),
        label: const Value('Sunscreen'),
        position: const Value(0),
        createdBy: const Value(userId),
        createdAt: Value(now),
      ),
    );

    await db.upsertListItem(
      LocalTripListItemsCompanion(
        id: const Value('list-1'),
        checkedBy: const Value(userId),
        checkedAt: Value(now),
      ),
    );
    var row = await db.watchTripListItems(tripId).first;
    expect(row.single.checkedBy, userId);

    await db.upsertListItem(
      const LocalTripListItemsCompanion(
        id: Value('list-1'),
        checkedBy: Value(null),
        checkedAt: Value(null),
      ),
    );
    row = await db.watchTripListItems(tripId).first;
    expect(row.single.checkedBy, isNull);
  });

  test('setEventRsvp flushes pending plan item before RPC', () async {
    final calls = <String>[];
    const planItemId = 'event-1';
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    await queue.enqueue(
      kind: SyncKind.planItemUpsert,
      payload: {'id': planItemId},
    );
    final worker = SyncWorker(
      queue: queue,
      client: client,
      analytics: DebugAnalytics(),
      flushWithoutSession: true,
      testExecute: (op) async {
        calls.add('flush:${op.kind}');
      },
    );
    final repo = PlanRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      syncQueue: queue,
      syncWorker: worker,
      currentUserIdOverride: 'user-1',
      rpcOverride: (functionName, params) async {
        calls.add('rpc:$functionName:${params['p_plan_item_id']}');
      },
    );

    await repo.setEventRsvp(
      planItemId: planItemId,
      status: EventRsvpStatus.going,
    );

    expect(calls, [
      'flush:plan_item_upsert',
      'rpc:set_event_rsvp:$planItemId',
    ]);
  });

  test('setEventRsvp fails before RPC when target plan item stays pending',
      () async {
    final calls = <String>[];
    const planItemId = 'event-1';
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    await queue.enqueue(
      kind: SyncKind.planItemUpsert,
      payload: {'id': planItemId},
    );
    final worker = SyncWorker(
      queue: queue,
      client: client,
      analytics: DebugAnalytics(),
      flushWithoutSession: true,
      testExecute: (op) async {
        calls.add('flush:${op.kind}');
        throw StateError('still offline');
      },
    );
    final repo = PlanRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      syncQueue: queue,
      syncWorker: worker,
      currentUserIdOverride: 'user-1',
      rpcOverride: (functionName, params) async {
        calls.add('rpc:$functionName');
      },
    );

    await expectLater(
      repo.setEventRsvp(
        planItemId: planItemId,
        status: EventRsvpStatus.going,
      ),
      throwsA(isA<StateError>()),
    );

    expect(calls, ['flush:plan_item_upsert']);
  });
}
