import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../trips/trips_providers.dart';
import 'expense_models.dart';
import 'expenses_repository.dart';
final allExpensesProvider = StreamProvider<List<ExpenseSummary>>((ref) {
  return ref.watch(expensesRepositoryProvider).watchAllExpenses();
});

/// Trip id → display name for cross-trip expense rows.
final tripNameMapProvider = Provider<Map<String, String>>((ref) {
  final trips = ref.watch(tripsListProvider).valueOrNull ?? [];
  return {for (final t in trips) t.id: t.name};
});
