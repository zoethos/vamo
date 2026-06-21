import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('main shell has five nav slots and a centered FAB',
      (tester) async {
    final router = GoRouter(
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => MainShell(
            navigationShell: shell,
            labels: const MainShellLabels(
              trips: 'Trips',
              activity: 'Activity',
              add: 'Add',
              expenses: 'Expenses',
              profile: 'Profile',
              createTrip: 'Create trip',
              addExpense: 'Add expense',
              addExpensePickerTitle: 'Choose trip',
              addExpenseLastUsed: 'Last used',
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

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
