import 'package:feature_split/src/trips/compact_trip_card.dart';
import 'package:feature_split/src/trips/dashboard_activity_row.dart';
import 'package:feature_split/src/trips/featured_trip_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_theme.dart';
import 's35_screen_previews.dart';

void main() {
  const phone = Size(360, 640);
  const tablet = Size(800, 600);

  Future<void> pumpSurface(
    WidgetTester tester, {
    required Widget child,
    required Size surface,
    Brightness brightness = Brightness.light,
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      Directionality(
        textDirection: textDirection,
        child: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('S35 My Trips goldens', () {
    testWidgets('featured trip light small', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        child: pumpFeaturedTripCard(theme: goldenTestTheme()),
      );
      await expectLater(
        find.byType(FeaturedTripCard),
        matchesGoldenFile('goldens/s35_featured_trip_light_small.png'),
      );
    });

    testWidgets('featured trip dark small', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        child: pumpFeaturedTripCard(
          theme: goldenTestTheme(brightness: Brightness.dark),
        ),
      );
      await expectLater(
        find.byType(FeaturedTripCard),
        matchesGoldenFile('goldens/s35_featured_trip_dark_small.png'),
      );
    });

    testWidgets('compact trip light rtl', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        textDirection: TextDirection.rtl,
        child: pumpCompactTripCard(theme: goldenTestTheme()),
      );
      await expectLater(
        find.byType(CompactTripCard),
        matchesGoldenFile('goldens/s35_compact_trip_light_rtl.png'),
      );
    });
  });

  group('S35 dashboard goldens', () {
    testWidgets('activity row light', (tester) async {
      await pumpSurface(
        tester,
        surface: tablet,
        child: pumpDashboardActivityRow(theme: goldenTestTheme()),
      );
      await expectLater(
        find.byType(DashboardActivityRow),
        matchesGoldenFile('goldens/s35_activity_row_light.png'),
      );
    });

    testWidgets('activity row dark rtl', (tester) async {
      await pumpSurface(
        tester,
        surface: tablet,
        textDirection: TextDirection.rtl,
        child: pumpDashboardActivityRow(
          theme: goldenTestTheme(brightness: Brightness.dark),
        ),
      );
      await expectLater(
        find.byType(DashboardActivityRow),
        matchesGoldenFile('goldens/s35_activity_row_dark_rtl.png'),
      );
    });
  });
}
