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

import 'golden_test_theme.dart';

class _GoldenFakePoiRepository implements PoiRepository {
  _GoldenFakePoiRepository({this.result});

  final PoiDiscoveryResult? result;

  @override
  Future<PoiDiscoveryResult?> searchForTrip({
    required String tripId,
    required String query,
    String? regionBias,
    String? category,
    String? sessionId,
  }) async =>
      result;

  @override
  Future<PoiDiscoveryResult?> discoverNearby({
    required String tripId,
    required double lat,
    required double lng,
    String? query,
    String? category,
    int? radius,
  }) async =>
      throw UnimplementedError();
}

void main() {
  const phone = Size(360, 640);

  testWidgets('plan sheet visit search light small', (tester) async {
    final fakePoiRepository = _GoldenFakePoiRepository(
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
          distanceM: 240,
        ),
      ]),
    );

    await tester.binding.setSurfaceSize(phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          theme: goldenTestTheme(),
          home: Scaffold(
            body: PlanItemSheet(
              tripId: 'trip-1',
              labels: _goldenLabels,
              existing: null,
              readOnly: false,
              onSave: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(_goldenLabels.kindVisit));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('visitPlaceSearchField')),
      'mari',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/plan_sheet_visit_search_light_small.png'),
    );
  });
}

final _goldenLabels = PlanTabLabels(
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
      '$going going · $maybe maybe · $declined declined',
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
