typedef BudgetBurnDownLabel = String Function(int remainingCents, String currency);
typedef BudgetOverLabel = String Function(String currency);
typedef BudgetFormalConfirmHint = String Function(String phrase);

class TripBudgetLabels {
  const TripBudgetLabels({
    required this.settingsTitle,
    required this.budgetSectionTitle,
    required this.budgetModeNone,
    required this.budgetModeInformational,
    required this.budgetModeFormal,
    required this.budgetAmountLabel,
    required this.saveBudget,
    required this.burnDownRemaining,
    required this.burnDownOver,
    required this.fxSectionTitle,
    required this.fxAddCurrency,
    required this.fxRefresh,
    required this.fxCapturedAt,
    required this.fxSource,
    required this.fxRateReadOnly,
    required this.overBudgetCommitTitle,
    required this.overBudgetCommitBody,
    required this.overBudgetConfirmHint,
    required this.overBudgetConfirmPhrase,
    required this.confirm,
    required this.cancel,
    required this.currencyMissingAdmin,
  });

  final String settingsTitle;
  final String budgetSectionTitle;
  final String budgetModeNone;
  final String budgetModeInformational;
  final String budgetModeFormal;
  final String budgetAmountLabel;
  final String saveBudget;
  final BudgetBurnDownLabel burnDownRemaining;
  final BudgetOverLabel burnDownOver;
  final String fxSectionTitle;
  final String fxAddCurrency;
  final String fxRefresh;
  final String Function(String capturedAtIso) fxCapturedAt;
  final String fxSource;
  final String fxRateReadOnly;
  final String overBudgetCommitTitle;
  final String overBudgetCommitBody;
  final BudgetFormalConfirmHint overBudgetConfirmHint;
  final String overBudgetConfirmPhrase;
  final String confirm;
  final String cancel;
  final String currencyMissingAdmin;
}
