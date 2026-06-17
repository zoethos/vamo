import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/capture/capture_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _SheetHost extends StatefulWidget {
  const _SheetHost({
    required this.tripId,
    required this.child,
  });

  final String tripId;
  final Widget Function(
    BuildContext context,
    Future<void> Function() onDismiss,
  ) child;

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  var _open = true;

  @override
  Widget build(BuildContext context) {
    if (!_open) return const SizedBox.shrink();
    return widget.child(context, () async {
      setState(() => _open = false);
    });
  }
}

Future<void> _selectCarouselItem(
  WidgetTester tester, {
  required int dragSteps,
}) async {
  final wheel = find.byType(ListWheelScrollView);
  if (dragSteps > 0) {
    await tester.drag(wheel, Offset(0, -80.0 * dragSteps));
    await tester.pumpAndSettle();
  }
  await tester.tapAt(tester.getCenter(find.byType(CaptureChoiceSheet)));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Future<void> pumpOverlay(WidgetTester tester) async {
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
    await pumpOverlay(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ListWheelScrollView), findsOneWidget);
    expect(find.byType(VamoCircleIcon), findsWidgets);
    expect(find.byType(CaptureChoiceSheet), findsOneWidget);
    expect(find.byType(VamoCarousel), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
  });

  testWidgets('outside tap dismisses capture flyout', (tester) async {
    await pumpOverlay(tester);

    expect(find.byType(CaptureChoiceSheet), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.byType(CaptureChoiceSheet), findsNothing);
  });

  group('picker failure reports action_failed and dismisses carousel', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required List<Map<String, Object?>> events,
      required Widget Function(
        BuildContext context,
        Future<void> Function() onDismiss,
      ) buildSheet,
    }) async {
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
              body: _SheetHost(
                tripId: 'trip-1',
                child: buildSheet,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final pickerError = PlatformException(
      code: 'photo_access_denied',
      message: 'User denied access',
    );

    testWidgets('photo', (tester) async {
      final events = <Map<String, Object?>>[];
      await pumpSheet(
        tester,
        events: events,
        buildSheet: (context, onDismiss) => CaptureChoiceSheet(
          tripId: 'trip-1',
          navigationContext: context,
          providerContainer: ProviderScope.containerOf(context, listen: false),
          onDismiss: onDismiss,
          pickImage: ({
            required source,
            maxWidth,
            maxHeight,
            imageQuality,
          }) async {
            throw pickerError;
          },
        ),
      );

      await _selectCarouselItem(tester, dragSteps: 0);

      expect(find.byType(CaptureChoiceSheet), findsNothing);
      expect(
        events
            .where((e) => e['event'] == VamoEvent.actionFailed)
            .single['properties'],
        {
          'screen': 'trip_home',
          'action': 'add_capture_photo',
          'severity': 'failure',
          'error_kind': 'app',
          'error_code': 'platform_exception',
        },
      );
    });

    testWidgets('video', (tester) async {
      final events = <Map<String, Object?>>[];
      await pumpSheet(
        tester,
        events: events,
        buildSheet: (context, onDismiss) => CaptureChoiceSheet(
          tripId: 'trip-1',
          navigationContext: context,
          providerContainer: ProviderScope.containerOf(context, listen: false),
          onDismiss: onDismiss,
          pickVideo: ({required source, maxDuration}) async {
            throw pickerError;
          },
        ),
      );

      await _selectCarouselItem(tester, dragSteps: 1);

      expect(find.byType(CaptureChoiceSheet), findsNothing);
      expect(
        events
            .where((e) => e['event'] == VamoEvent.actionFailed)
            .single['properties'],
        {
          'screen': 'trip_home',
          'action': 'add_capture_video',
          'severity': 'failure',
          'error_kind': 'app',
          'error_code': 'platform_exception',
        },
      );
    });

    testWidgets('background', (tester) async {
      final events = <Map<String, Object?>>[];
      await pumpSheet(
        tester,
        events: events,
        buildSheet: (context, onDismiss) => CaptureChoiceSheet(
          tripId: 'trip-1',
          navigationContext: context,
          providerContainer: ProviderScope.containerOf(context, listen: false),
          onDismiss: onDismiss,
          pickImage: ({
            required source,
            maxWidth,
            maxHeight,
            imageQuality,
          }) async {
            throw pickerError;
          },
        ),
      );

      await _selectCarouselItem(tester, dragSteps: 3);

      expect(find.byType(CaptureChoiceSheet), findsNothing);
      expect(
        events
            .where((e) => e['event'] == VamoEvent.actionFailed)
            .single['properties'],
        {
          'screen': 'trip_home',
          'action': 'set_trip_background',
          'severity': 'failure',
          'error_kind': 'app',
          'error_code': 'platform_exception',
        },
      );
    });

    testWidgets('picker cancel emits capture_action_abandoned cancelled', (
      tester,
    ) async {
      final events = <Map<String, Object?>>[];
      await pumpSheet(
        tester,
        events: events,
        buildSheet: (context, onDismiss) => CaptureChoiceSheet(
          tripId: 'trip-1',
          navigationContext: context,
          providerContainer: ProviderScope.containerOf(context, listen: false),
          onDismiss: onDismiss,
          pickImage: ({
            required source,
            maxWidth,
            maxHeight,
            imageQuality,
          }) async {
            return null;
          },
        ),
      );

      await _selectCarouselItem(tester, dragSteps: 0);

      expect(find.byType(CaptureChoiceSheet), findsOneWidget);
      expect(events, [
        {
          'event': VamoEvent.captureActionAbandoned,
          'properties': {
            'screen': 'trip_home',
            'action': 'add_capture_photo',
            'reason': 'cancelled',
          },
        },
      ]);
    });

    testWidgets('note dismisses before navigation failure is reported', (
      tester,
    ) async {
      final events = <Map<String, Object?>>[];
      await pumpSheet(
        tester,
        events: events,
        buildSheet: (context, onDismiss) => CaptureChoiceSheet(
          tripId: 'trip-1',
          navigationContext: context,
          providerContainer: ProviderScope.containerOf(context, listen: false),
          onDismiss: onDismiss,
        ),
      );

      await _selectCarouselItem(tester, dragSteps: 2);

      expect(find.byType(CaptureChoiceSheet), findsNothing);
      expect(
        events
            .where((e) => e['event'] == VamoEvent.actionFailed)
            .single['properties'],
        {
          'screen': 'trip_home',
          'action': 'add_capture_note',
          'severity': 'failure',
          'error_kind': 'app',
          'error_code': 'assertion_error',
        },
      );
      expect(
        events
            .where((e) => e['event'] == VamoEvent.captureActionStarted)
            .single['properties'],
        {
          'screen': 'trip_home',
          'action': 'add_capture_note',
          'sheet_mounted': true,
        },
      );
    });
  });
}
