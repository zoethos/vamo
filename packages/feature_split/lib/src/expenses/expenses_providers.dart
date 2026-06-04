import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'expense_models.dart';
import 'expenses_repository.dart';

final tripExpensesProvider =
    StreamProvider.family<List<ExpenseSummary>, String>((ref, tripId) {
  return ref.watch(expensesRepositoryProvider).watchTripExpenses(tripId);
});

final tripMembersForExpenseProvider =
    StreamProvider.family<List<TripMemberView>, String>((ref, tripId) {
  return ref.watch(expensesRepositoryProvider).watchActiveMembers(tripId);
});
