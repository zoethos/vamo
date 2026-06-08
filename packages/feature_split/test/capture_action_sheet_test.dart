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

  testWidgets(
      'capture choice flyout shows vertical wheel with centered noun label',
      (tester) async {
    await pumpSheet(tester);

    expect(find.byType(BottomSheet), findsNothing);

    expect(find.byType(ListWheelScrollView), findsOneWidget);

    expect(find.byType(VamoCircleIcon), findsWidgets);

    expect(find.byType(CaptureChoiceSheet), findsOneWidget);

    expect(find.text('Photo'), findsOneWidget);

    expect(find.text('Add note'), findsNothing);

    expect(find.text('Add photo'), findsNothing);
  });

  testWidgets('only the centered item shows a visible text label', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Video'), findsNothing);
    expect(find.text('Note'), findsNothing);
    expect(find.text('Background'), findsNothing);
  });

  testWidgets('centered label respects large text scaler without overflow',
      (tester) async {
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
          analyticsProvider.overrideWithValue(DebugAnalytics()),
        ],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: Center(
                child: CaptureChoiceSheet(tripId: 'trip-1'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('Photo'));
    expect(label.maxLines, 1);
    expect(find.ancestor(of: find.text('Photo'), matching: find.byType(FittedBox)),
        findsOneWidget);
  });

  testWidgets('long centered label scales down to fit the pill', (tester) async {
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
          analyticsProvider.overrideWithValue(DebugAnalytics()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Center(
              child: CaptureChoiceSheet(tripId: 'trip-1'),
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
  });

  testWidgets('capture carousel exposes semantic labels for every option',
      (tester) async {
    await pumpSheet(tester);

    for (final label in ['Photo', 'Video', 'Note', 'Background']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
  });

  testWidgets('semantic options are buttons reachable without scrolling',
      (tester) async {
    await pumpSheet(tester);

    for (final label in ['Photo', 'Video', 'Note', 'Background']) {
      final data =
          tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
    }
  });

  testWidgets('capture wheel is finite and does not wrap end-to-start',
      (tester) async {
    await pumpSheet(tester);

    final wheel =
        tester.widget<ListWheelScrollView>(find.byType(ListWheelScrollView));
    expect(
      wheel.childDelegate.estimatedChildCount,
      4,
    );
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
