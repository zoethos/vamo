import 'package:feature_split/feature_split.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/shared/vamo_slidable_row.dart';
import 'package:feature_split/src/trips/member_avatar_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
  kindVisit: 'Visit',
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

  group('S38 bottom nav goldens', () {
    Future<void> pumpNav(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
      TextDirection textDirection = TextDirection.ltr,
    }) async {
      final router = GoRouter(
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => MainShell(
              navigationShell: shell,
              labels: const MainShellLabels(
                trips: 'Trips',
                activity: 'Activity',
                expenses: 'Expenses',
                profile: 'Profile',
              ),
            ),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/',
                    builder: (_, __) => const Scaffold(body: Text('trips')),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/activity',
                    builder: (_, __) => const Scaffold(body: Text('activity')),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/expenses',
                    builder: (_, __) => const Scaffold(body: Text('expenses')),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/profile',
                    builder: (_, __) => const Scaffold(body: Text('profile')),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      await pumpSurface(
        tester,
        surface: phone,
        brightness: brightness,
        textDirection: textDirection,
        child: ProviderScope(
          child: MaterialApp.router(
            theme: goldenTestTheme(brightness: brightness),
            routerConfig: router,
          ),
        ),
      );
    }

    testWidgets('nav strip light small', (tester) async {
      await pumpNav(tester);
      await expectLater(
        find.byType(BottomAppBar),
        matchesGoldenFile('goldens/s38_nav_light_small.png'),
      );
    });

    testWidgets('nav strip dark small', (tester) async {
      await pumpNav(tester, brightness: Brightness.dark);
      await expectLater(
        find.byType(BottomAppBar),
        matchesGoldenFile('goldens/s38_nav_dark_small.png'),
      );
    });

    testWidgets('nav strip light rtl', (tester) async {
      await pumpNav(tester, textDirection: TextDirection.rtl);
      await expectLater(
        find.byType(BottomAppBar),
        matchesGoldenFile('goldens/s38_nav_light_rtl.png'),
      );
    });
  });

  group('S38 avatar goldens', () {
    testWidgets('member avatar row person silhouette light', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        child: MaterialApp(
          theme: goldenTestTheme(),
          home: Scaffold(
            body: MemberAvatarRow(
              members: const [
                TripMemberView(
                  userId: '1',
                  displayName: 'Vamo',
                  role: 'owner',
                ),
                TripMemberView(
                  userId: '2',
                  displayName: 'Alex',
                  role: 'member',
                ),
              ],
              onAdd: () {},
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(MemberAvatarRow),
        matchesGoldenFile('goldens/s38_avatar_row_light_small.png'),
      );
    });

    testWidgets('member avatar row dark', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        brightness: Brightness.dark,
        child: MaterialApp(
          theme: goldenTestTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: MemberAvatarRow(
              members: const [
                TripMemberView(
                  userId: '1',
                  displayName: '',
                  role: 'member',
                ),
              ],
              onAdd: () {},
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(MemberAvatarRow),
        matchesGoldenFile('goldens/s38_avatar_row_dark_small.png'),
      );
    });
  });

  group('S38 plan header goldens', () {
    testWidgets('plan screen header add light', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        child: MaterialApp(
          theme: goldenTestTheme(),
          home: Scaffold(
            appBar: AppBar(
              title: Text(_planLabels.tabTitle),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: _planLabels.addPlanItem,
                  onPressed: () {},
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _planLabels.checklistsSection,
                  style: goldenTestTextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Card(
                  child: CheckboxListTile(
                    value: false,
                    onChanged: (_) {},
                    title: const Text('Passport'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/s38_plan_header_light_small.png'),
      );
    });
  });

  group('S38 slidable row goldens', () {
    testWidgets('swiped edit delete light', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        child: MaterialApp(
          theme: goldenTestTheme(),
          home: Scaffold(
            body: VamoSlidableRow(
              editLabel: 'Edit',
              deleteLabel: 'Delete',
              deleteConfirmTitle: 'Delete this item?',
              deleteConfirmAction: 'Delete',
              cancelLabel: 'Cancel',
              onEdit: () {},
              onDelete: () {},
              child: const Card(
                child: ListTile(
                  title: Text('Dinner reservation'),
                  subtitle: Text('7:30 PM · Old Town'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.text('Dinner reservation'), const Offset(-120, 0));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(VamoSlidableRow),
        matchesGoldenFile('goldens/s38_slidable_delete_light_small.png'),
      );
    });

    testWidgets('swiped edit dark', (tester) async {
      await pumpSurface(
        tester,
        surface: phone,
        brightness: Brightness.dark,
        child: MaterialApp(
          theme: goldenTestTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: VamoSlidableRow(
              editLabel: 'Edit',
              deleteLabel: 'Delete',
              deleteConfirmTitle: 'Delete this item?',
              deleteConfirmAction: 'Delete',
              cancelLabel: 'Cancel',
              onEdit: () {},
              onDelete: () {},
              child: const Card(
                child: ListTile(
                  title: Text('Train to Positano'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.text('Train to Positano'), const Offset(120, 0));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(VamoSlidableRow),
        matchesGoldenFile('goldens/s38_slidable_edit_dark_small.png'),
      );
    });
  });
}
