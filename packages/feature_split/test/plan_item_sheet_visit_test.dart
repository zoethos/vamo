import 'package:app_core/app_core.dart';
import 'package:feature_split/src/plan/plan_item_sheet.dart';
import 'package:feature_split/src/plan/plan_labels.dart';
import 'package:feature_split/src/plan/plan_models.dart';
import 'package:feature_split/src/plan/plan_providers.dart';
import 'package:feature_split/src/poi/poi_models.dart';
import 'package:feature_split/src/poi/poi_providers.dart';
import 'package:feature_split/src/poi/poi_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('visit manual fields stay editable without POI API calls', (
    tester,
  ) async {
    PlanItemInput? saved;
    final fakePoiRepository = _FakePoiRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planItemCapabilitiesProvider.overrideWith(
            (ref) async => PlanItemCapabilities.fallbackByKind(),
          ),
          tripResolvedPlacesProvider.overrideWith(
            (ref, tripId) => const Stream.empty(),
          ),
          poiRepositoryProvider.overrideWithValue(fakePoiRepository),
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

    expect(
      find.widgetWithText(FilledButton, _labels.ctaTapType),
      findsOneWidget,
    );

    await tester.tap(find.text(_labels.kindVisit));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, _labels.ctaTapPlace),
      findsOneWidget,
    );
    expect(find.text(_labels.visitFindCoordinates), findsNothing);
    expect(find.text(_labels.visitDiscoverNearby), findsNothing);
    expect(find.byKey(const Key('visitPlaceSearchField')), findsOneWidget);
    expect(find.text(_labels.visitDiscoverHelper), findsNothing);
    expect(find.byKey(const Key('visitAddNoteRow')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('visitPlaceSearchField')),
      'Marienplatz',
    );
    await tester.enterText(
      find.byKey(const Key('visitAddressField')),
      'Marienplatz, Munich',
    );

    expect(find.text('Marienplatz'), findsOneWidget);
    expect(find.text('Marienplatz, Munich'), findsOneWidget);

    final saveButton = find.widgetWithText(FilledButton, _labels.visitSave);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved?.kind, PlanItemKind.visit);
    expect(saved?.title, 'Marienplatz');
    expect(saved?.metadata['place_label'], 'Marienplatz');
    expect(saved?.metadata['address'], 'Marienplatz, Munich');
    expect(saved?.metadata['lat'], isNull);
    expect(saved?.metadata['lng'], isNull);
  });

  testWidgets('visit search debounces and maps selected POI to metadata', (
    tester,
  ) async {
    PlanItemInput? saved;
    final fakePoiRepository = _FakePoiRepository(
      result: const PoiDiscoveryResult.available([
        PoiSummary(
          id: 'fsq-marienplatz',
          name: 'Marienplatz',
          category: PoiCategory.attraction,
          lat: 48.1374,
          lng: 11.5755,
          source: 'foursquare',
          providerPlaceId: 'fsq:123',
          address: 'Marienplatz 1, Munich',
        ),
      ]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planItemCapabilitiesProvider.overrideWith(
            (ref) async => PlanItemCapabilities.fallbackByKind(),
          ),
          tripResolvedPlacesProvider.overrideWith(
            (ref, tripId) => const Stream.empty(),
          ),
          poiRepositoryProvider.overrideWithValue(fakePoiRepository),
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

    await tester.tap(find.text(_labels.kindVisit));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('visitPlaceSearchField')),
      'mar',
    );
    await tester.pump(const Duration(milliseconds: 299));
    expect(fakePoiRepository.searchCalls, 0);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fakePoiRepository.searchCalls, 1);
    expect(fakePoiRepository.lastTripId, 'trip-1');
    expect(fakePoiRepository.lastQuery, 'mar');
    expect(fakePoiRepository.lastSessionId, isNotEmpty);
    expect(find.text('Marienplatz'), findsOneWidget);
    expect(find.text(_labels.visitDiscoverNeedsCoordinates), findsNothing);

    final suggestion = find.text('Marienplatz');
    await tester.ensureVisible(suggestion.first);
    await tester.tap(suggestion.first);
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, _labels.visitSave);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved?.title, 'Marienplatz');
    expect(saved?.metadata['place_label'], 'Marienplatz');
    expect(saved?.metadata['address'], 'Marienplatz 1, Munich');
    expect(saved?.metadata['lat'], 48.1374);
    expect(saved?.metadata['lng'], 11.5755);
    expect(saved?.metadata['place_id'], 'fsq:123');
  });
}

class _FakePoiRepository implements PoiRepository {
  _FakePoiRepository({this.result});

  final PoiDiscoveryResult? result;
  int searchCalls = 0;
  String? lastTripId;
  String? lastQuery;
  String? lastSessionId;

  @override
  Future<PoiDiscoveryResult?> searchForTrip({
    required String tripId,
    required String query,
    String? regionBias,
    String? category,
    String? sessionId,
  }) async {
    searchCalls++;
    lastTripId = tripId;
    lastQuery = query;
    lastSessionId = sessionId;
    return result;
  }

  @override
  Future<PoiDiscoveryResult?> discoverNearby({
    required String tripId,
    required double lat,
    required double lng,
    String? query,
    String? category,
    int? radius,
  }) async {
    throw UnimplementedError('Nearby search is not used by the visit sheet.');
  }
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
  visitCoordinatesNotFound: 'Could not find that place.',
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
  ctaTapType: 'tap a type',
  ctaTapPlace: 'tap a place',
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
