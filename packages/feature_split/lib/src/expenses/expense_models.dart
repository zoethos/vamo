import 'package:app_core/app_core.dart';

import 'expense_governance.dart';

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
    required this.status,
    this.receiptPath,
    this.localReceiptPath,
    this.capturedLat,
    this.capturedLng,
    this.capturedAt,
    this.placeLabel,
    this.placeId,
    this.category,
    this.fxRateSource = 'auto',
    this.fxRateManual,
    this.fxConversionLocked = false,
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
  final ExpenseStatus status;
  final String? receiptPath;
  final String? localReceiptPath;
  final double? capturedLat;
  final double? capturedLng;
  final DateTime? capturedAt;
  final String? placeLabel;
  final String? placeId;
  final String? category;

  /// `auto` | `receipt` | `manual` — how [baseCents] was chosen (S50).
  final String fxRateSource;
  final double? fxRateManual;
  final bool fxConversionLocked;

  String? get displayPlaceLabel => placeLabel;

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
    this.avatarUrl,
    this.avatarDisplayMode = AvatarDisplayMode.photo,
    this.avatarInitials,
  });

  final String userId;
  final String displayName;
  final String role;

  /// Storage path in the private `avatars` bucket — never a signed URL.
  final String? avatarUrl;
  final AvatarDisplayMode avatarDisplayMode;
  final String? avatarInitials;
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
    this.placeLabel,
    this.placeId,
    this.ocrUsed = false,
    this.manualBaseCents,
    this.fxRateSource,
    this.lockConversion = false,
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
  final String? placeLabel;
  final String? placeId;
  final bool ocrUsed;

  /// Editor override for trip-base cents (S50 manual/receipt path).
  final int? manualBaseCents;
  final String? fxRateSource;
  final bool lockConversion;
}

/// Result of [ExpensesRepository.addExpense].
class AddExpenseResult {
  const AddExpenseResult({required this.expenseId});

  final String expenseId;
}
