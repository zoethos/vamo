import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/trips/featured_trip_card.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:feature_split/src/weather/weather_models.dart';
import 'package:feature_split/src/weather/weather_overlay.dart';
import 'package:feature_split/src/weather/weather_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_theme.dart';
import 'weather_labels_test_support.dart';

TripSummary weatherGoldenTrip({required String id}) {
  final start = DateTime.now().toUtc().add(const Duration(days: 3));
  return TripSummary(
    id: id,
    name: 'Amalfi Coast',
    destination: 'Italy',
    startDate: start.toIso8601String().substring(0, 10),
    endDate: start.add(const Duration(days: 7)).toIso8601String().substring(0, 10),
    baseCurrency: 'EUR',
  );
}

Widget pumpFeaturedTripWeatherGolden({
  required ThemeData theme,
  required ConditionBucket bucket,
  required String goldenId,
}) {
  final trip = weatherGoldenTrip(id: 'weather-golden-$goldenId');
  return ProviderScope(
    overrides: [
      tripsSyncProvider.overrideWith((ref) async {}),
      tripsListProvider.overrideWith((ref) => Stream.value([trip])),
      tripCardBackgroundImageProvider(trip.id).overrideWith((ref) => null),
      tripMembersForExpenseProvider(trip.id).overrideWith(
        (ref) => Stream.value([
          const TripMemberView(
            userId: 'owner-1',
            displayName: 'Owner',
            role: 'owner',
          ),
          const TripMemberView(
            userId: 'member-2',
            displayName: 'Member',
            role: 'member',
          ),
        ]),
      ),
      weatherFeaturedOverlayEnabledProvider.overrideWith((ref) => true),
      weatherPreviewProvider(trip.id).overrideWith(
        (ref) async => WeatherPreview(bucket: bucket, tempHigh: 24),
      ),
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: FeaturedTripCard(
              trip: trip,
              participantsLabel: (count) => '$count Vamigos',
              weatherLabels: testWeatherBadgeLabels,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const phone = Size(360, 640);

  Future<void> pumpSurface(
    WidgetTester tester, {
    required Widget child,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(child);
    await tester.pump();
  }

  group('H-P1 weather overlay goldens', () {
    for (final bucket in ConditionBucket.values) {
      if (bucket == ConditionBucket.unknown) continue;

      testWidgets('featured card ${bucket.name} light', (tester) async {
        await pumpSurface(
          tester,
          child: pumpFeaturedTripWeatherGolden(
            theme: goldenTestTheme(),
            bucket: bucket,
            goldenId: '${bucket.name}_light',
          ),
        );

        expect(find.text('Amalfi Coast'), findsOneWidget);
        expect(find.byType(GradientScrim), findsOneWidget);

        await expectLater(
          find.byType(FeaturedTripCard),
          matchesGoldenFile(
            'goldens/h_p1_featured_weather_${bucket.name}_light.png',
          ),
        );
      });

      testWidgets('featured card ${bucket.name} dark', (tester) async {
        await pumpSurface(
          tester,
          child: pumpFeaturedTripWeatherGolden(
            theme: goldenTestTheme(brightness: Brightness.dark),
            bucket: bucket,
            goldenId: '${bucket.name}_dark',
          ),
          brightness: Brightness.dark,
        );

        expect(find.text('Amalfi Coast'), findsOneWidget);
        expect(find.byType(GradientScrim), findsOneWidget);

        await expectLater(
          find.byType(FeaturedTripCard),
          matchesGoldenFile(
            'goldens/h_p1_featured_weather_${bucket.name}_dark.png',
          ),
        );
      });
    }
  });
}
