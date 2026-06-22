import 'package:feature_split/src/capture/capture_models.dart';
import 'package:feature_split/src/capture/capture_providers.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/map/trip_map_screen.dart';
import 'package:feature_split/src/plan/plan_models.dart';
import 'package:feature_split/src/plan/plan_providers.dart';
import 'package:feature_split/src/sync/trip_realtime_binding.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'trip_home_labels_test_support.dart';

const _tripId = 't1';

/// A 1×1 transparent PNG so the map never touches the network in tests.
final _transparentPixel = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _OfflineTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_transparentPixel);
}

TripDetail _trip({String? start, String? end}) => TripDetail(
      id: _tripId,
      name: 'Roman Holiday',
      destination: 'Rome',
      startDate: start,
      endDate: end,
      baseCurrency: 'EUR',
      ownerId: 'u1',
    );

List<Override> _overrides({
  required TripDetail detail,
  List<PlanItemSummary> planItems = const [],
}) {
  return [
    tripRealtimeBindingProvider.overrideWith((ref, tripId) {}),
    tripDetailProvider.overrideWith((ref, tripId) => Stream.value(detail)),
    tripPlanItemsProvider.overrideWith((ref, tripId) => Stream.value(planItems)),
    tripExpensesProvider.overrideWith((ref, tripId) => Stream.value(const [])),
    tripResolvedPlacesProvider
        .overrideWith((ref, tripId) => Stream.value(const [])),
    tripPhotosProvider
        .overrideWith((ref, tripId) => Stream.value(const <TripPhotoView>[])),
    // Avoid the real geocoding plugin in tests.
    tripDestinationCoordsProvider.overrideWith((ref, tripId) async => null),
  ];
}

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        home: TripMapScreen(
          tripId: _tripId,
          tripHomeLabels: testTripHomeLabels,
          tileProvider: _OfflineTileProvider(),
        ),
      ),
    ),
  );
  // A couple of frames so the stream values resolve and the map lays out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('renders the map and a calm empty overlay when no moments lands',
      (tester) async {
    await _pump(tester, _overrides(detail: _trip()));

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(
      find.text('Your journey appears here as you go.'),
      findsOneWidget,
    );
  });

  testWidgets('plots a placed visit and shows the day scrubber',
      (tester) async {
    final visit = PlanItemSummary(
      id: 'v1',
      tripId: _tripId,
      kind: PlanItemKind.visit,
      title: 'Pantheon',
      startsAt: DateTime(2026, 6, 2, 10),
      metadata:
          buildVisitPlaceMetadata(placeLabel: 'Pantheon', lat: 41.9, lng: 12.47),
      position: 0,
    );

    await _pump(
      tester,
      _overrides(
        detail: _trip(start: '2026-06-01', end: '2026-06-03'),
        planItems: [visit],
      ),
    );

    // Marker rendered (visit icon) and no empty overlay.
    expect(find.byIcon(Icons.place), findsOneWidget);
    expect(find.text('Your journey appears here as you go.'), findsNothing);

    // Day scrubber present for a multi-day trip.
    expect(find.text('All days'), findsOneWidget);
    expect(find.text('Day 1 of 3'), findsOneWidget);
  });
}
