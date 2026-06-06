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
    required this.proposeCostAction,
    required this.addExpenseTitle,
    required this.proposeCostTitle,
    required this.saveExpense,
    required this.saveProposal,
    required this.tripBalancesIn,
    required this.splitEqual,
    required this.splitSolo,
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
  final String proposeCostAction;
  final String addExpenseTitle;
  final String proposeCostTitle;
  final String saveExpense;
  final String saveProposal;
  final String Function(String currency) tripBalancesIn;
  final String Function(int memberCount) splitEqual;
  final String splitSolo;

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
