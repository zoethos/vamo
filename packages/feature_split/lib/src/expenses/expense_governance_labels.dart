import 'expense_governance.dart';

/// User-facing copy for expense consent / proposal flows (S19.1 i18n bundle).
class ExpenseGovernanceLabels {
  const ExpenseGovernanceLabels({
    required this.includedDisputedBy,
    required this.includedPendingFrom,
    required this.someoneFallback,
    required this.proposalRowPrefix,
    required this.proposalNotInBalances,
    required this.shareAccepted,
    required this.yourShare,
    required this.dispute,
    required this.accept,
    required this.commitToBalances,
    required this.voidProposal,
    required this.disputeReasonTitle,
    required this.disputeReasonHint,
    required this.cancel,
    required this.submit,
    required this.addExpenseAction,
    required this.proposeExpenseAction,
    required this.addExpenseTitle,
    required this.proposeExpenseTitle,
    required this.saveExpense,
    required this.saveProposal,
    required this.tripBalancesIn,
    required this.splitEqual,
    required this.splitSolo,
    required this.convertedAmountLabel,
    required this.fxConversionLocked,
    required this.saveConversion,
    required this.fxSourceReceipt,
    required this.totalSpent,
    required this.filterAll,
    required this.filterUnsettled,
    required this.filterMine,
    required this.todayLabel,
  });

  final String Function(String memberName) includedDisputedBy;
  final String Function(String memberName) includedPendingFrom;
  final String someoneFallback;
  final String proposalRowPrefix;
  final String proposalNotInBalances;
  final String shareAccepted;
  final String yourShare;
  final String dispute;
  final String accept;
  final String commitToBalances;
  final String voidProposal;
  final String disputeReasonTitle;
  final String disputeReasonHint;
  final String cancel;
  final String submit;

  /// Committed-path CTA ("Add expense"). The expense saves directly.
  final String addExpenseAction;

  /// Proposal-path CTA ("Propose expense"). Only in [AddExpenseMode.proposed],
  /// where the flow enters the consent path.
  final String proposeExpenseAction;
  final String addExpenseTitle;
  final String proposeExpenseTitle;
  final String saveExpense;
  final String saveProposal;
  final String Function(String currency) tripBalancesIn;
  final String Function(int memberCount) splitEqual;
  final String splitSolo;
  final String Function(String currency) convertedAmountLabel;
  final String fxConversionLocked;
  final String saveConversion;
  final String fxSourceReceipt;

  /// Spend-led summary header (§B) — "Total spent". "Your share" reuses
  /// [yourShare].
  final String totalSpent;

  /// Day-grouped list filter chips (§C).
  final String filterAll;
  final String filterUnsettled;
  final String filterMine;

  /// Day-group header token for the current day ("Today").
  final String todayLabel;

  /// CTA label for the action FAB, chosen by [mode] (§0 verb decision).
  String actionLabel(AddExpenseMode mode) =>
      mode == AddExpenseMode.proposed ? proposeExpenseAction : addExpenseAction;

  String consentDisplayLabel({
    required String memberName,
    required ShareResponse response,
  }) {
    return switch (response) {
      ShareResponse.rejected => includedDisputedBy(memberName),
      ShareResponse.pending => includedPendingFrom(memberName),
      ShareResponse.accepted => '',
    };
  }

  String splitLabel(int memberCount) =>
      memberCount == 1 ? splitSolo : splitEqual(memberCount);
}

enum AddExpenseMode { committed, proposed }
