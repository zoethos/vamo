import 'package:app_core/app_core.dart';
import 'package:feature_split/src/travel/advanced_travel_labels.dart';
import 'package:feature_split/src/travel/advanced_travel_section.dart';
import 'package:feature_split/src/travel/travel_leg.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _labels = AdvancedTravelLabels(
  toggleTitle: "Plan how you'll travel",
  toggleBadge: 'Advanced',
  toggleSubtitle: 'Multi-modal legs',
  legsSectionTitle: 'Travel legs',
  legsInOrder: 'in order',
  addLeg: 'Add leg',
  noLegs: 'No legs yet',
  draftWithAi: 'Draft route with AI',
  draftWithAiBadge: 'Vamo AI',
  draftComingSoon: 'Coming soon',
  planItMyself: "I'll plan it myself",
  aiFootnote: 'AI is optional',
  legEditorTitle: 'Travel leg',
  removeLeg: 'Remove',
  modeSectionTitle: 'Mode',
  windowSectionTitle: 'When you can travel',
  windowAnyTime: 'Any time',
  windowOptionalHint: 'Times optional',
  reachSectionTitle: 'Reach limit',
  reachDistance: 'Distance',
  reachTime: 'Time',
  reachNoLimit: 'No limit',
  reachDistanceCaption: "max you'll cover",
  reachTimeCaption: 'max per day',
  reachHoursUnit: 'h / day',
  unitsFootnote: 'Units follow your profile',
  saveLeg: 'Save leg',
  modeCar: 'Car',
  modeMotorbike: 'Motorbike',
  modeBike: 'Bike',
  modeTrain: 'Train',
  modeFlight: 'Flight',
  modeBus: 'Bus',
  reviewTitle: 'Route draft',
  reviewSubtitle: 'Pick the stops to add.',
  reviewWarningsTitle: 'Heads up',
  reviewQuestionsTitle: 'Open questions',
  reviewAddToPlan: 'Add to plan',
  reviewSkip: 'Not now',
  reviewCommitting: 'Adding…',
  reviewEmpty: 'No stops were drafted.',
  draftGatedMessage: 'Out of free drafts.',
  draftFailedMessage: 'Could not draft.',
);

Future<void> _pumpSection(
  WidgetTester tester, {
  required List<TravelLeg> legs,
  required ValueChanged<List<TravelLeg>> onChanged,
  Set<TravelMode> modes = const {TravelMode.car, TravelMode.train},
  ValueChanged<Set<TravelMode>>? onModesChanged,
  DistanceUnit unit = DistanceUnit.km,
  DateTime? tripStart,
  DateTime? tripEnd,
}) async {
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdvancedTravelSection(
            labels: _labels,
            modes: modes,
            onModesChanged: onModesChanged ?? (_) {},
            legs: legs,
            onChanged: onChanged,
            unit: unit,
            tripStart: tripStart,
            tripEnd: tripEnd,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('empty state offers an Add leg affordance', (tester) async {
    await _pumpSection(tester, legs: const [], onChanged: (_) {});
    expect(find.text('Add a travel leg'), findsOneWidget);
  });

  testWidgets('renders a leg row with mode label and window·reach summary', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      legs: [
        TravelLeg(
          mode: TravelMode.train,
          windowStart: DateTime.utc(2026, 7, 4),
          windowEnd: DateTime.utc(2026, 7, 7),
          reach: const ReachLimit.hoursPerDay(5),
        ),
      ],
      onChanged: (_) {},
    );
    expect(find.text('Train'), findsWidgets);
    expect(find.textContaining('Jul 4 – 7'), findsOneWidget);
    expect(find.textContaining('≤ 5h / day'), findsOneWidget);
  });

  testWidgets('mode chips toggle the selected mode set', (tester) async {
    Set<TravelMode>? captured;
    await _pumpSection(
      tester,
      legs: const [],
      modes: const {},
      onChanged: (_) {},
      onModesChanged: (modes) => captured = modes,
    );

    await tester.tap(find.text('Train'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured, contains(TravelMode.train));
  });

  testWidgets('add → save emits a new default leg', (tester) async {
    List<TravelLeg>? captured;
    await _pumpSection(
      tester,
      legs: const [],
      onChanged: (legs) => captured = legs,
    );

    await tester.tap(find.text('Add a travel leg'));
    await tester.pumpAndSettle();
    expect(find.text('Travel leg'), findsOneWidget);

    await tester.tap(find.text('Save leg'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.length, 1);
    expect(captured!.single.mode, TravelMode.car);
    expect(captured!.single.reach.type, ReachType.distance);
    expect(captured!.single.reach.value, 600);
  });

  testWidgets('new leg defaults to the gap after the previous leg', (
    tester,
  ) async {
    List<TravelLeg>? captured;
    await _pumpSection(
      tester,
      legs: [
        TravelLeg(
          mode: TravelMode.car,
          windowStart: DateTime.utc(2026, 5, 12),
          windowEnd: DateTime.utc(2026, 5, 14),
          reach: const ReachLimit.distanceKm(600),
        ),
      ],
      onChanged: (legs) => captured = legs,
      unit: DistanceUnit.km,
      tripStart: DateTime.utc(2026, 5, 12),
      tripEnd: DateTime.utc(2026, 5, 18),
    );

    await tester.tap(find.text('Add a travel leg'));
    await tester.pumpAndSettle();
    expect(find.text('Travel leg'), findsOneWidget);

    await tester.tap(find.text('Save leg'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.length, 2);
    expect(
      DateUtils.dateOnly(captured!.last.windowStart!),
      DateTime(2026, 5, 15),
    );
    expect(
      DateUtils.dateOnly(captured!.last.windowEnd!),
      DateTime(2026, 5, 18),
    );
  });

  test('reach summaries render in miles when unit is miles', () {
    final summary = legReachSummary(
      const TravelLeg(
        mode: TravelMode.car,
        reach: ReachLimit.distanceKm(300),
      ),
      DistanceUnit.miles,
      _labels,
    );

    expect(summary, '≤ 186 mi');
  });
}
