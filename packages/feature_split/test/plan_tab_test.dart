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
    kindOther: 'Other',
    sheetTitleAdd: 'Add plan item',
    sheetTitleEdit: 'Edit plan item',
    fieldTitle: 'Title',
    fieldNotes: 'Notes',
    fieldStart: 'Starts',
    fieldEnd: 'Ends',
    save: 'Save',
    loadError: 'Could not load the plan.',
    checklistsLoadError: 'Could not load checklists.',
    rsvpGoing: 'Going',
    rsvpMaybe: 'Maybe',
    rsvpDeclined: 'Declined',
    rsvpSummary: (going, maybe) => '$going going · $maybe maybe',
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
}
