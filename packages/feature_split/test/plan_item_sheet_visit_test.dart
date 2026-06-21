import 'package:app_core/app_core.dart';
import 'package:feature_split/src/plan/plan_item_sheet.dart';
import 'package:feature_split/src/plan/plan_labels.dart';
import 'package:feature_split/src/plan/plan_models.dart';
import 'package:feature_split/src/plan/plan_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('visit manual fields stay editable without POI API calls',
      (tester) async {
    PlanItemInput? saved;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planItemCapabilitiesProvider.overrideWith(
            (ref) async => PlanItemCapabilities.fallbackByKind(),
          ),
          tripResolvedPlacesProvider.overrideWith(
            (ref, tripId) => const Stream.empty(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PlanItemSheet(
              tripId: 'trip-1',
              labels: _labels,
              existing: null,
              readOnly: false,
              onSave: (input) async => saved = input,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButton<PlanItemKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_labels.kindVisit).last);
    await tester.pumpAndSettle();

    expect(find.text(_labels.visitFindCoordinates), findsNothing);
    expect(find.text(_labels.visitPlaceHelper), findsOneWidget);
    expect(find.text(_labels.visitAddressHelper), findsOneWidget);
    expect(find.text(_labels.visitDiscoverHelper), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, _labels.visitPlaceLabel),
      'Marienplatz',
    );
    await tester.enterText(
      find.widgetWithText(TextField, _labels.visitAddressLabel),
      'Marienplatz, Munich',
    );
    await tester.enterText(
      find.widgetWithText(TextField, _labels.fieldTitle),
      'Morning visit',
    );

    expect(find.text('Marienplatz'), findsOneWidget);
    expect(find.text('Marienplatz, Munich'), findsOneWidget);

    final saveButton = find.widgetWithText(FilledButton, _labels.save);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved?.kind, PlanItemKind.visit);
    expect(saved?.title, 'Morning visit');
    expect(saved?.metadata['place_label'], 'Marienplatz');
    expect(saved?.metadata['address'], 'Marienplatz, Munich');
  });

  testWidgets('discover nearby asks for human place input, not coordinates',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planItemCapabilitiesProvider.overrideWith(
            (ref) async => PlanItemCapabilities.fallbackByKind(),
          ),
          tripResolvedPlacesProvider.overrideWith(
            (ref, tripId) => const Stream.empty(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PlanItemSheet(
              tripId: 'trip-1',
              labels: _labels,
              existing: null,
              readOnly: false,
              onSave: (_) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButton<PlanItemKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_labels.kindVisit).last);
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithText(OutlinedButton, _labels.visitDiscoverNearby));
    await tester.pumpAndSettle();

    expect(find.text(_labels.visitDiscoverNeedsPlace), findsOneWidget);
    expect(find.text(_labels.visitDiscoverNeedsCoordinates), findsNothing);
  });
}

final _labels = PlanTabLabels(
  tabTitle: 'Plan',
  emptyTitle: 'Nothing on the board yet',
  emptySubtitle: 'Add items for the group.',
  undatedSection: 'No date',
  checklistsSection: 'Checklists',
  addPlanItem: 'Add to plan',
  addListItemHint: 'New checklist item',
  defaultListName: 'Packing',
  deleteItem: 'Delete',
  editItem: 'Edit',
  kindLodging: 'Lodging',
  kindFlight: 'Flight',
  kindTrain: 'Train',
  kindActivity: 'Activity',
  kindVisit: 'Visit',
  kindTransfer: 'Transfer',
  kindOther: 'Other',
  sheetTitleAdd: 'Add plan item',
  sheetTitleEdit: 'Edit plan item',
  fieldTitle: 'Title',
  fieldKind: 'Type',
  fieldNotes: 'Notes',
  fieldStart: 'Starts',
  fieldEnd: 'Ends',
  visitSectionTitle: 'Visit details',
  visitFromTripPlaces: 'From this trip',
  visitPlaceLabel: 'Place',
  visitAddressLabel: 'Address',
  visitFindCoordinates: 'Find coordinates',
  visitPlaceRequired: 'Add a place for the visit.',
  visitAddressRequiredForGeocode: 'Add an address first.',
  visitCoordinatesSaved: 'Coordinates saved.',
  visitCoordinatesNotFound: 'Could not find coordinates.',
  visitDiscoverNeedsCoordinates: 'Find coordinates first.',
  transferSectionTitle: 'Transfer details',
  transferSubtypeLabel: 'Subtype',
  transferOriginLabel: 'From',
  transferDestinationLabel: 'To',
  transferProviderLabel: 'Provider',
  transferReferenceLabel: 'Reference',
  transferSubtypeCarRental: 'Car rental',
  transferSubtypeTrain: 'Train',
  transferSubtypeTransit: 'Transit',
  transferSubtypeDrive: 'Drive',
  transferSubtypeFlight: 'Flight',
  save: 'Save',
  loadError: 'Could not load the plan.',
  checklistsLoadError: 'Could not load checklists.',
  rsvpGoing: 'Going',
  rsvpMaybe: 'Maybe',
  rsvpDeclined: 'Declined',
  rsvpSummary: (going, maybe, declined) =>
      '$going going - $maybe maybe - $declined declined',
  eventRsvpHint: 'RSVP after save',
  eventRsvpSection: 'RSVP',
  eventRsvpUpdateFailed: 'Could not update RSVP. Try again.',
  datePickerCancel: 'Cancel',
  datePickerSkip: 'Skip',
  datePickerSelect: 'Select',
  addChecklistItem: 'Add checklist item',
  deleteConfirmTitle: 'Delete this item?',
  endBeforeStart: 'End must be on or after start.',
  cancelLabel: 'Cancel',
);
