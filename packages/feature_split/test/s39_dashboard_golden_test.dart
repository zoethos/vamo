import 'package:feature_split/src/trips/trip_dashboard_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_theme.dart';
import 's35_screen_previews.dart';

void main() {
  const phone = Size(360, 640);

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

  group('S41 dashboard goldens', () {
    testWidgets('dashboard light small', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        child: pumpTripDashboardTab(theme: goldenTestTheme()),
      );
      await expectLater(
        find.byType(TripDashboardTab),
        matchesGoldenFile('goldens/s39_dashboard_light_small.png'),
      );
    });

    testWidgets('dashboard dark small', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        child: pumpTripDashboardTab(
          theme: goldenTestTheme(brightness: Brightness.dark),
        ),
      );
      await expectLater(
        find.byType(TripDashboardTab),
        matchesGoldenFile('goldens/s39_dashboard_dark_small.png'),
      );
    });

    testWidgets('dashboard light rtl', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        textDirection: TextDirection.rtl,
        child: pumpTripDashboardTab(theme: goldenTestTheme()),
      );
      await expectLater(
        find.byType(TripDashboardTab),
        matchesGoldenFile('goldens/s39_dashboard_light_rtl.png'),
      );
    });
  });
}
