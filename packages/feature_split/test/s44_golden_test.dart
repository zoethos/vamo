import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/capture/capture_action_sheet.dart';
import 'package:feature_split/src/trips/trip_visual_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'golden_test_theme.dart';

void main() {
  const phone = Size(360, 640);
  const heroSize = Size(360, 220);

  final heroFixturePath = p.normalize(
    p.join(Directory.current.path, 'test', 'fixtures', 'hero_bg.png'),
  );

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

  Widget carouselSheet({
    required Brightness brightness,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    return MaterialApp(
      theme: goldenTestTheme(brightness: brightness),
      home: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(
                  AppDatabase.forTesting(NativeDatabase.memory()),
                ),
                supabaseClientProvider.overrideWithValue(
                  SupabaseClient(
                    'http://localhost',
                    'anon-key',
                    authOptions:
                        const AuthClientOptions(autoRefreshToken: false),
                  ),
                ),
                analyticsProvider.overrideWithValue(DebugAnalytics()),
              ],
              child: const CaptureChoiceSheet(tripId: 'trip-1'),
            ),
          ),
        ),
      ),
    );
  }

  Widget heroWithScrim({
    required String backgroundPath,
    Brightness brightness = Brightness.light,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    return MaterialApp(
      theme: goldenTestTheme(brightness: brightness),
      home: Directionality(
        textDirection: textDirection,
        child: SizedBox(
          width: heroSize.width,
          height: heroSize.height,
          child: TripVisualBackdrop(
            tripName: 'Amalfi Coast',
            destination: 'Italy',
            backgroundImagePath: backgroundPath,
            child: const Stack(
              fit: StackFit.expand,
              children: [
                GradientScrim(heightFactor: 0.85),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Text(
                    'Amalfi Coast',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  group('S44 capture carousel goldens', () {
    testWidgets('carousel menu light small', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        child: carouselSheet(brightness: Brightness.light),
      );
      await expectLater(
        find.byType(CaptureChoiceSheet),
        matchesGoldenFile('goldens/s44_capture_carousel_light_small.png'),
      );
    });

    testWidgets('carousel menu dark rtl', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        textDirection: TextDirection.rtl,
        child: carouselSheet(
          brightness: Brightness.dark,
          textDirection: TextDirection.rtl,
        ),
      );
      await expectLater(
        find.byType(CaptureChoiceSheet),
        matchesGoldenFile('goldens/s44_capture_carousel_dark_rtl.png'),
      );
    });
  });

  group('S44 hero background goldens', () {
    testWidgets('hero user background light small', (tester) async {
      await pumpSurface(
        tester,
        surface: heroSize,
        child: heroWithScrim(backgroundPath: heroFixturePath),
      );
      await expectLater(
        find.byType(TripVisualBackdrop),
        matchesGoldenFile('goldens/s44_hero_background_light_small.png'),
      );
    });

    testWidgets('hero user background dark rtl', (tester) async {
      await pumpSurface(
        tester,
        surface: heroSize,
        textDirection: TextDirection.rtl,
        child: heroWithScrim(
          backgroundPath: heroFixturePath,
          brightness: Brightness.dark,
          textDirection: TextDirection.rtl,
        ),
      );
      await expectLater(
        find.byType(TripVisualBackdrop),
        matchesGoldenFile('goldens/s44_hero_background_dark_rtl.png'),
      );
    });
  });
}
