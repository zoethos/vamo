/// Expense row for the trip home list (from Drift).
class ExpenseSummary {
  const ExpenseSummary({
    required this.id,
    required this.tripId,
    required this.description,
    required this.amountCents,
    required this.baseCents,
    required this.currency,
    required this.payerId,
    required this.spentAt,
    this.receiptPath,
    this.localReceiptPath,
    this.capturedLat,
    this.capturedLng,
    this.capturedAt,
  });

  final String id;
  final String tripId;
  final String description;

  /// Original spend amount in [currency].
  final int amountCents;

  /// Converted amount in the trip's base currency.
  final int baseCents;

  /// ISO 4217 code of the currency actually spent.
  final String currency;
  final String payerId;
  final DateTime spentAt;
  final String? receiptPath;
  final String? localReceiptPath;
  final double? capturedLat;
  final double? capturedLng;
  final DateTime? capturedAt;

  bool get hasReceipt =>
      (receiptPath != null && receiptPath!.isNotEmpty) ||
      (localReceiptPath != null && localReceiptPath!.isNotEmpty);
}

/// Active trip member for payer picker and equal split.
class TripMemberView {
  const TripMemberView({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String role;
}

class AddExpenseInput {
  const AddExpenseInput({
    required this.tripId,
    required this.description,
    required this.amountCents,
    required this.expenseCurrency,
    required this.payerId,
    this.category,
    this.spentAt,
    this.receiptSourcePath,
    this.capturedLat,
    this.capturedLng,
    this.capturedAt,
  });

  final String tripId;
  final String description;
  final int amountCents;
  final String expenseCurrency;
  final String payerId;
  final String? category;
  final DateTime? spentAt;
  final String? receiptSourcePath;
  final double? capturedLat;
  final double? capturedLng;
  final DateTime? capturedAt;
}

/// Result of [ExpensesRepository.addExpense].
class AddExpenseResult {
  const AddExpenseResult({required this.expenseId});

  final String expenseId;
}
