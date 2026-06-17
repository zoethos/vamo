import 'package:feature_split/src/capture/capture_models.dart';
import 'package:feature_split/src/capture/capture_providers.dart';
import 'package:feature_split/src/capture/capture_tab.dart';
import 'package:feature_split/src/plan/event_rsvp_models.dart';
import 'package:feature_split/src/plan/plan_event_rsvp_picker.dart';
import 'package:feature_split/src/plan/plan_event_tile.dart';
import 'package:feature_split/src/plan/plan_labels.dart';
import 'package:feature_split/src/plan/plan_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_theme.dart';

final _planLabels = PlanTabLabels(
  tabTitle: 'Plan',
  emptyTitle: 'Nothing on the board yet',
  emptySubtitle: 'Add lodging, transport, or activities for the group.',
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
  kindOther: 'Other',
  sheetTitleAdd: 'Add plan item',
  sheetTitleEdit: 'Edit plan item',
  fieldTitle: 'Title',
  fieldKind: 'Type',
  fieldNotes: 'Notes',
  fieldStart: 'Starts',
  fieldEnd: 'Ends',
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

void main() {
  const phone = Size(360, 640);

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

  Future<void> finishSurface(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('S43 memories goldens', () {
    testWidgets('memories empty light small', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        child: _memoriesPreview(theme: goldenTestTheme()),
      );
      await expectLater(
        find.byType(CaptureTab),
        matchesGoldenFile('goldens/s43_memories_empty_light_small.png'),
      );
      await finishSurface(tester);
    });

    testWidgets('memories empty dark small', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        brightness: Brightness.dark,
        child: _memoriesPreview(
          theme: goldenTestTheme(brightness: Brightness.dark),
        ),
      );
      await expectLater(
        find.byType(CaptureTab),
        matchesGoldenFile('goldens/s43_memories_empty_dark_small.png'),
      );
      await finishSurface(tester);
    });

    testWidgets('memories with note light rtl', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        textDirection: TextDirection.rtl,
        child: _memoriesPreview(
          theme: goldenTestTheme(),
          notes: [
            TripNoteView(
              id: 'note-1',
              tripId: 'trip-amalfi',
              title: 'Sunset spot',
              body: 'Best view from the terrace after dinner.',
              capturedAt: DateTime.utc(2026, 7, 12),
            ),
          ],
        ),
      );
      await expectLater(
        find.byType(CaptureTab),
        matchesGoldenFile('goldens/s43_memories_note_light_rtl.png'),
      );
      await finishSurface(tester);
    });
  });

  group('S43 plan RSVP goldens', () {
    testWidgets('rsvp state icons light small', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        child: MaterialApp(
          theme: goldenTestTheme(),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  PlanEventRsvpStateIcon(
                    myStatus: null,
                    unsetLabel: 'RSVP',
                  ),
                  PlanEventRsvpStateIcon(
                    myStatus: EventRsvpStatus.going,
                    unsetLabel: 'RSVP',
                  ),
                  PlanEventRsvpStateIcon(
                    myStatus: EventRsvpStatus.maybe,
                    unsetLabel: 'RSVP',
                  ),
                  PlanEventRsvpStateIcon(
                    myStatus: EventRsvpStatus.declined,
                    unsetLabel: 'RSVP',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(Wrap),
        matchesGoldenFile('goldens/s43_rsvp_states_light_small.png'),
      );
    });

    testWidgets('compact event card light small', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        child: _planEventTilePreview(
          theme: goldenTestTheme(),
          myStatus: EventRsvpStatus.going,
        ),
      );
      await expectLater(
        find.byType(PlanEventTile),
        matchesGoldenFile('goldens/s43_plan_event_tile_light_small.png'),
      );
    });

    testWidgets('compact event card dark rtl', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        textDirection: TextDirection.rtl,
        child: _planEventTilePreview(
          theme: goldenTestTheme(brightness: Brightness.dark),
          myStatus: EventRsvpStatus.maybe,
        ),
      );
      await expectLater(
        find.byType(PlanEventTile),
        matchesGoldenFile('goldens/s43_plan_event_tile_dark_rtl.png'),
      );
    });
  });
}

Widget _memoriesPreview({
  required ThemeData theme,
  List<TripNoteView> notes = const [],
  List<TripPhotoView> photos = const [],
  List<TripVideoView> videos = const [],
}) {
  return ProviderScope(
    overrides: [
      tripNotesProvider.overrideWith((ref, tripId) => Stream.value(notes)),
      tripPhotosProvider.overrideWith((ref, tripId) => Stream.value(photos)),
      tripVideosProvider.overrideWith((ref, tripId) => Stream.value(videos)),
    ],
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        appBar: AppBar(title: const Text('Memories')),
        body: const CaptureTab(
          tripId: 'trip-amalfi',
          showInlineAddActions: false,
        ),
      ),
    ),
  );
}

Widget _planEventTilePreview({
  required ThemeData theme,
  required EventRsvpStatus? myStatus,
}) {
  final view = PlanItemEventView(
    item: PlanItemSummary(
      id: 'event-1',
      tripId: 'trip-1',
      kind: PlanItemKind.activity,
      title: 'Beach day',
      notes: 'Bring sunscreen',
      startsAt: DateTime.utc(2026, 6, 12, 14),
      position: 0,
    ),
    counts: const EventRsvpCounts(going: 3, maybe: 1, declined: 1),
    myStatus: myStatus,
  );

  return ProviderScope(
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PlanEventTile(
              tripId: 'trip-1',
              view: view,
              labels: _planLabels,
              readOnly: false,
              onEdit: () {},
              onDelete: () {},
            ),
          ],
        ),
      ),
    ),
  );
}
