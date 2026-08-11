import 'expense_models.dart';
import 'expense_split.dart';

enum ExpenseSplitMode { equal, custom }

/// Pure draft state for an add-expense split. It has no widget or persistence
/// dependency, so the UI and repository share the same validation boundary.
class ExpenseSplitState {
  const ExpenseSplitState({
    required this.mode,
    this.customShareCents = const {},
  });

  final ExpenseSplitMode mode;
  final Map<String, int> customShareCents;

  List<ExpenseShareLine> resolve({
    required int baseCents,
    required List<TripMemberView> members,
  }) {
    final memberIds = members.map((member) => member.userId).toList();
    if (mode == ExpenseSplitMode.equal) {
      return equalSplit(baseCents: baseCents, memberIds: memberIds);
    }
    return validateCustomSplit(
      baseCents: baseCents,
      memberIds: memberIds,
      shares: [
        for (final member in members)
          ExpenseShareLine(
            userId: member.userId,
            shareCents: customShareCents[member.userId] ?? -1,
          ),
      ],
    );
  }

  String? validationMessage({
    required int? baseCents,
    required List<TripMemberView> members,
  }) {
    if (mode != ExpenseSplitMode.custom) return null;
    if (baseCents == null || baseCents <= 0) {
      return 'Enter an amount before setting a custom split.';
    }
    try {
      resolve(baseCents: baseCents, members: members);
      return null;
    } on ArgumentError catch (error) {
      return error.message?.toString() ?? 'Update the custom split.';
    } on StateError catch (error) {
      return error.message;
    }
  }
}
