import '../expenses/expense_governance.dart';

enum TripBudgetMode {
  none,
  informational,
  formal;

  static TripBudgetMode parse(String? raw) {
    return TripBudgetMode.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => TripBudgetMode.none,
    );
  }

  bool get hasBurnDown =>
      this == TripBudgetMode.informational || this == TripBudgetMode.formal;
}

class TripBudgetBurnDown {
  const TripBudgetBurnDown({
    required this.mode,
    required this.budgetCents,
    required this.committedSpendCents,
    required this.remainingCents,
    required this.isOverBudget,
  });

  final TripBudgetMode mode;
  final int? budgetCents;
  final int committedSpendCents;
  final int remainingCents;
  final bool isOverBudget;

  static TripBudgetBurnDown compute({
    required TripBudgetMode mode,
    required int? budgetCents,
    required Iterable<int> committedBaseCents,
  }) {
    final spent = committedBaseCents.fold<int>(0, (a, b) => a + b);
    if (!mode.hasBurnDown || budgetCents == null || budgetCents <= 0) {
      return TripBudgetBurnDown(
        mode: mode,
        budgetCents: budgetCents,
        committedSpendCents: spent,
        remainingCents: 0,
        isOverBudget: false,
      );
    }
    final remaining = budgetCents - spent;
    return TripBudgetBurnDown(
      mode: mode,
      budgetCents: budgetCents,
      committedSpendCents: spent,
      remainingCents: remaining,
      isOverBudget: remaining < 0,
    );
  }
}

/// Formal mode flag only — commit is never blocked at the DB (D2).
bool wouldExceedFormalBudget({
  required TripBudgetMode mode,
  required int? budgetCents,
  required int committedSpendCents,
  required int additionalBaseCents,
}) {
  if (mode != TripBudgetMode.formal || budgetCents == null || budgetCents <= 0) {
    return false;
  }
  return committedSpendCents + additionalBaseCents > budgetCents;
}

bool canManageTripBudgetAndFx({
  required bool tripReadOnly,
  required String? memberRole,
}) =>
    !tripReadOnly && memberRole != null && canEditTripProposals(memberRole);
