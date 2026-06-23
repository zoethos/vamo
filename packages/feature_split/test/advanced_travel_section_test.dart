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

const _datePickerLabels = VamoDatePickerLabels(
  cancel: 'Cancel',
  skip: 'Skip',
  select: 'Select',
);

Future<void> _pumpSection(
  WidgetTester tester, {
  required List<TravelLeg> legs,
  required ValueChanged<List<TravelLeg>> onChanged,
  DistanceUnit unit = DistanceUnit.km,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdvancedTravelSection(
            labels: _labels,
            legs: legs,
            onChanged: onChanged,
            unit: unit,
            datePickerLabels: _datePickerLabels,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('empty state offers an Add leg affordance', (tester) async {
    await _pumpSection(tester, legs: const [], onChanged: (_) {});
    expect(find.text('No legs yet'), findsOneWidget);
    expect(find.text('Add leg'), findsOneWidget);
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
    expect(find.text('Train'), findsOneWidget);
    expect(find.textContaining('Jul 4 – Jul 7'), findsOneWidget);
    expect(find.textContaining('≤ 5 h / day'), findsOneWidget);
  });

  testWidgets('add → pick mode + reach → save emits a new leg', (tester) async {
    List<TravelLeg>? captured;
    await _pumpSection(
      tester,
      legs: const [],
      onChanged: (legs) => captured = legs,
    );

    await tester.tap(find.text('Add leg'));
    await tester.pumpAndSettle();
    expect(find.text('Travel leg'), findsOneWidget);

    await tester.tap(find.text('Train'));
    await tester.pump();
    await tester.ensureVisible(find.text('300 km'));
    await tester.tap(find.text('300 km')); // a distance preset (canonical km)
    await tester.pump();
    await tester.ensureVisible(find.text('Save leg'));
    await tester.tap(find.text('Save leg'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.length, 1);
    expect(captured!.single.mode, TravelMode.train);
    expect(captured!.single.reach.type, ReachType.distance);
    expect(captured!.single.reach.value, 300);
  });

  testWidgets('distance presets render in miles when unit is miles', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      legs: const [],
      onChanged: (_) {},
      unit: DistanceUnit.miles,
    );
    await tester.tap(find.text('Add leg'));
    await tester.pumpAndSettle();

    // 300 km preset → ~186 mi chip label.
    expect(find.textContaining('mi'), findsWidgets);
    expect(find.text('300 km'), findsNothing);
  });
}
