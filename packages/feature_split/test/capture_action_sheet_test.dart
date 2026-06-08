import 'package:app_core/app_core.dart';

import 'package:drift/native.dart';

import 'package:feature_split/src/capture/capture_action_sheet.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Future<void> pumpSheet(WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    addTearDown(db.close);

    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          supabaseClientProvider.overrideWithValue(client),
          analyticsProvider.overrideWithValue(DebugAnalytics()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showCaptureActionSheet(
                    context: context,
                    tripId: 'trip-1',
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));

    await tester.pumpAndSettle();
  }

  testWidgets('capture flyout opens generic carousel shell', (tester) async {
    await pumpSheet(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ListWheelScrollView), findsOneWidget);
    expect(find.byType(VamoCircleIcon), findsWidgets);
    expect(find.byType(CaptureChoiceSheet), findsOneWidget);
    expect(find.byType(VamoCarousel), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
  });

  testWidgets('outside tap dismisses capture flyout', (tester) async {
    await pumpSheet(tester);

    expect(find.byType(CaptureChoiceSheet), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.byType(CaptureChoiceSheet), findsNothing);
  });

  testWidgets(
    'background picker failure reports classified set_trip_background action_failed',
    (tester) async {
      final events = <Map<String, Object?>>[];
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            supabaseClientProvider.overrideWithValue(
              SupabaseClient(
                'http://localhost',
                'anon-key',
                authOptions: const AuthClientOptions(autoRefreshToken: false),
              ),
            ),
            analyticsProvider.overrideWithValue(_RecordingAnalytics(events)),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(
                child: CaptureChoiceSheet(
                  tripId: 'trip-1',
                  pickImage: ({
                    required source,
                    maxWidth,
                    maxHeight,
                    imageQuality,
                  }) async {
                    throw PlatformException(
                      code: 'photo_access_denied',
                      message: 'User denied access',
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final wheel = find.byType(ListWheelScrollView);
      await tester.drag(wheel, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(find.text('Background'), findsOneWidget);

      await tester.tapAt(tester.getCenter(find.byType(CaptureChoiceSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(events, [
        {
          'event': VamoEvent.actionFailed,
          'properties': {
            'screen': 'trip_home',
            'action': 'set_trip_background',
            'severity': 'failure',
            'error_kind': 'app',
            'error_code': 'platform_exception',
          },
        },
      ]);
    },
  );
}

class _RecordingAnalytics implements Analytics {
  _RecordingAnalytics(this.events);

  final List<Map<String, Object?>> events;

  @override
  void capture(VamoEvent event, {Map<String, Object?> properties = const {}}) {
    events.add({'event': event, 'properties': properties});
  }

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}
}
