import 'package:feature_split/src/trips/trips_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_theme.dart';
import 'trips_list_labels_test_support.dart';
import 'trips_list_test_support.dart';

void main() {
  const phone = Size(360, 640);

  final upcomingOnly = [
    TripSummary(
      id: 'upcoming-1',
      name: 'Amalfi Coast',
      startDate: '2099-07-10',
      endDate: '2099-07-17',
      baseCurrency: 'EUR',
    ),
  ];

  Future<void> pumpPastEmpty(WidgetTester tester, ThemeData theme) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      pumpTripsListScreen(trips: upcomingOnly, theme: theme),
    );
    await tester.pumpAndSettle();
    await tapFilter(tester, testTripsListLabels.filterPast);
  }

  testWidgets('filter row stays visible on empty past filter', (tester) async {
    await pumpPastEmpty(tester, goldenTestTheme());

    expect(find.byKey(const Key('trips_filter_row')), findsOneWidget);
    expect(find.text(testTripsListLabels.emptyPastTitle), findsOneWidget);
    expect(find.text(testTripsListLabels.filterDrafts), findsNothing);

    await tapFilter(tester, testTripsListLabels.filterAll);
    expect(find.text('Amalfi Coast'), findsOneWidget);
  });

  testWidgets('each filter keeps filter row and returns to All', (tester) async {
    final pastTrip = TripSummary(
      id: 'past-1',
      name: 'Rome weekend',
      startDate: '2020-01-01',
      endDate: '2020-01-04',
      baseCurrency: 'EUR',
    );

    await tester.pumpWidget(
      pumpTripsListScreen(trips: [pastTrip, ...upcomingOnly]),
    );
    await tester.pumpAndSettle();

    for (final filter in [
      testTripsListLabels.filterUpcoming,
      testTripsListLabels.filterPast,
    ]) {
      await tapFilter(tester, filter);
      expect(find.byKey(const Key('trips_filter_row')), findsOneWidget);

      await tapFilter(tester, testTripsListLabels.filterAll);
      expect(find.byKey(const Key('trips_filter_row')), findsOneWidget);
      expect(find.text('Amalfi Coast'), findsOneWidget);
      expect(find.text('Rome weekend'), findsOneWidget);
    }
  });

  group('trips list empty filter goldens', () {
    testWidgets('past filter empty light', (tester) async {
      await pumpPastEmpty(tester, goldenTestTheme());

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/trips_list_past_empty_light.png'),
      );
    });

    testWidgets('past filter empty dark', (tester) async {
      await pumpPastEmpty(tester, goldenTestTheme(brightness: Brightness.dark));

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/trips_list_past_empty_dark.png'),
      );
    });
  });
}
