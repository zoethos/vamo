import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/expenses/add_expense_screen.dart';
import 'package:feature_split/src/expenses/add_expense_screen_labels.dart';
import 'package:feature_split/src/expenses/expense_category_picker.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/expenses/expenses_repository.dart';
import 'package:feature_split/src/expenses/trip_expense_list_tile.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'governance_test_labels.dart';

class _SpyExpensesRepository extends ExpensesRepository {
  _SpyExpensesRepository({
    required super.db,
    required super.client,
    required super.analytics,
    required super.syncQueue,
    required super.syncWorker,
    required super.fxRates,
  });

  int addCalls = 0;
  String? lastAddedCategory;

  @override
  Future<AddExpenseResult> addExpense({
    required AddExpenseInput input,
    required String baseCurrency,
  }) async {
    addCalls++;
    lastAddedCategory = input.category;
    return const AddExpenseResult(expenseId: 'committed-id');
  }
}

const _screenLabels = AddExpenseScreenLabels(
  title: 'Add expense',
  tripNotFound: 'Trip not found',
  scanReceipt: 'Scan receipt',
  takePhoto: 'Take photo',
  chooseGallery: 'Choose from gallery',
  choosePayer: 'Choose who paid.',
);

void main() {
  test('multi-category rows produce multiple donut slices', () {
    final slices = buildCategoryDonutSlices(
      rows: const [
        (category: 'food', cents: 5000),
        (category: 'transport', cents: 3000),
        (category: 'other', cents: 2000),
      ],
      totalCents: 10000,
    );
    expect(slices, hasLength(3));
    expect(
      slices.map((s) => s.entry.key).toSet(),
      containsAll(['food', 'transport', 'other']),
    );
    expect(
      slices.fold<int>(0, (sum, slice) => sum + slice.cents),
      10000,
    );
  });

  testWidgets('expense list tile shows category icon when no receipt', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TripExpenseListTile(
              description: 'Lunch',
              payer: 'Alex',
              spentAt: DateTime(2026, 6, 7),
              baseCents: 1200,
              amountCents: 1200,
              tripBaseCurrency: 'EUR',
              expenseCurrency: 'EUR',
              category: 'food',
              proposalRowPrefix: 'Proposal',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.restaurant), findsOneWidget);
    expect(find.byKey(const Key('expense_receipt_thumbnail')), findsNothing);
  });

  testWidgets('add expense passes default other category on save',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final syncWorker = SyncWorker(
      queue: queue,
      client: client,
      analytics: DebugAnalytics(),
      flushWithoutSession: true,
      testExecute: (_) async {},
    );
    final spy = _SpyExpensesRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      syncQueue: queue,
      syncWorker: syncWorker,
      fxRates: FxRatesClient(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          supabaseClientProvider.overrideWithValue(client),
          analyticsProvider.overrideWithValue(DebugAnalytics()),
          expensesRepositoryProvider.overrideWith((ref) => spy),
          tripDetailProvider('trip-1').overrideWith(
            (ref) => Stream.value(
              const TripDetail(
                id: 'trip-1',
                name: 'Amalfi',
                baseCurrency: 'EUR',
                ownerId: 'owner',
                lifecycle: 'active',
              ),
            ),
          ),
          tripMembersForExpenseProvider('trip-1').overrideWith(
            (ref) => Stream.value([
              const TripMemberView(
                userId: 'owner',
                displayName: 'Alex',
                role: 'owner',
              ),
            ]),
          ),
          tripFxRatesProvider('trip-1').overrideWith((ref) => Stream.value([])),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: GoRouter(
            initialLocation: '/trips/trip-1/expenses/add',
            routes: [
              GoRoute(
                path: '/trips/:tripId',
                builder: (_, state) => Scaffold(
                  body: Text('trip-${state.pathParameters['tripId']}'),
                ),
                routes: [
                  GoRoute(
                    path: 'expenses/add',
                    builder: (_, state) => AddExpenseScreen(
                      tripId: state.pathParameters['tripId']!,
                      labels: governanceTestLabels,
                      screenLabels: _screenLabels,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, 'Pizza');
    await tester.tap(find.textContaining(governanceTestLabels.saveExpense));
    await tester.pumpAndSettle();

    expect(spy.addCalls, 1);
    expect(spy.lastAddedCategory, CategoryCatalog.other.key);
  });

  testWidgets('category picker selects food key', (tester) async {
    var selected = CategoryCatalog.other.key;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ExpenseCategoryPicker(
            selectedKey: selected,
            onChanged: (key) => selected = key,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final foodChip = find.byWidgetPredicate(
      (w) =>
          w is ChoiceChip &&
          find
              .descendant(
                of: find.byWidget(w),
                matching: find.text(CategoryCatalog.food.label),
              )
              .evaluate()
              .isNotEmpty,
    );
    await tester.tap(foodChip);
    await tester.pumpAndSettle();

    expect(selected, CategoryCatalog.food.key);
  });
}
