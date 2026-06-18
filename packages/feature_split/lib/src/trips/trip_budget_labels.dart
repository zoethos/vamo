typedef BudgetBurnDownLabel = String Function(
    int remainingCents, String currency);
typedef BudgetOverLabel = String Function(String currency);
typedef BudgetFormalConfirmHint = String Function(String phrase);
typedef RetentionOffloadResultLabel = String Function(int count);

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
    required this.datesSectionTitle,
    required this.startDateLabel,
    required this.endDateLabel,
    required this.saveDates,
    required this.startDateLockedHint,
    required this.endBeforeStart,
    required this.datePickerCancel,
    required this.datePickerSkip,
    required this.datePickerSelect,
    required this.retentionSectionTitle,
    required this.offloadMedia,
    required this.offloadMediaBody,
    required this.offloadMediaConfirmTitle,
    required this.offloadMediaConfirmBody,
    required this.offloadMediaSuccess,
    required this.offloadMediaNothing,
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
  final String datesSectionTitle;
  final String startDateLabel;
  final String endDateLabel;
  final String saveDates;
  final String startDateLockedHint;
  final String endBeforeStart;
  final String datePickerCancel;
  final String datePickerSkip;
  final String datePickerSelect;
  final String retentionSectionTitle;
  final String offloadMedia;
  final String offloadMediaBody;
  final String offloadMediaConfirmTitle;
  final String offloadMediaConfirmBody;
  final RetentionOffloadResultLabel offloadMediaSuccess;
  final String offloadMediaNothing;
}
