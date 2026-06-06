enum ExpenseStatus {
  proposed,
  committed,
  cancelled;

  static ExpenseStatus parse(String? raw) {
    return ExpenseStatus.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => ExpenseStatus.committed,
    );
  }

  bool get affectsBalances => this == ExpenseStatus.committed;
}

enum ShareResponse {
  pending,
  accepted,
  rejected;

  static ShareResponse parse(String? raw) {
    return ShareResponse.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => ShareResponse.accepted,
    );
  }

  bool get isConsentResolved => this == ShareResponse.accepted;
}

class ExpenseShareSummary {
  const ExpenseShareSummary({
    required this.id,
    required this.expenseId,
    required this.userId,
    required this.shareCents,
    required this.response,
    this.responseReason,
    this.respondedAt,
  });

  final String id;
  final String expenseId;
  final String userId;
  final int shareCents;
  final ShareResponse response;
  final String? responseReason;
  final DateTime? respondedAt;
}

bool canEditTripProposals(String role) =>
    role == 'owner' || role == 'co-admin';

/// Screen-level gate for the propose-expense form (role + writability).
bool canShowProposeExpenseForm({
  required bool tripReadOnly,
  required String? memberRole,
}) =>
    !tripReadOnly && memberRole != null && canEditTripProposals(memberRole);
