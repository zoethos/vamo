import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/plan/plan_labels.dart';
import 'package:feature_split/src/plan/plan_repository.dart';
import 'package:feature_split/src/plan/plan_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final labels = PlanTabLabels(
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

  testWidgets('read-only plan tab hides add controls', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final repo = PlanRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      syncQueue: queue,
      syncWorker: SyncWorker(
        queue: queue,
        client: client,
        analytics: DebugAnalytics(),
        flushWithoutSession: true,
        testExecute: (_) async {},
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsProvider.overrideWithValue(DebugAnalytics()),
          appDatabaseProvider.overrideWithValue(db),
          supabaseClientProvider.overrideWithValue(client),
          planRepositoryProvider.overrideWith((ref) => repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PlanTab(
              tripId: 'trip-1',
              labels: labels,
              readOnly: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(labels.addPlanItem), findsNothing);
    expect(find.text(labels.emptyTitle), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('hosted plan tab can hide its inline add action', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final repo = PlanRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      syncQueue: queue,
      syncWorker: SyncWorker(
        queue: queue,
        client: client,
        analytics: DebugAnalytics(),
        flushWithoutSession: true,
        testExecute: (_) async {},
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsProvider.overrideWithValue(DebugAnalytics()),
          appDatabaseProvider.overrideWithValue(db),
          supabaseClientProvider.overrideWithValue(client),
          planRepositoryProvider.overrideWith((ref) => repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PlanTab(
              tripId: 'trip-1',
              labels: labels,
              readOnly: false,
              showInlineAddAction: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(labels.emptyTitle), findsOneWidget);
    expect(find.text(labels.addPlanItem), findsNothing);
    expect(find.byType(FilledButton), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });
}
