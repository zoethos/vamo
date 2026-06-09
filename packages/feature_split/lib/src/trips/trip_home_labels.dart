/// Localized copy for trip home chrome (S27 / S35).
class TripHomeLabels {
  const TripHomeLabels({
    required this.tabOverview,
    required this.tabExpenses,
    required this.tabCapture,
    required this.memoriesTitle,
    required this.tabBalances,
    required this.tabMembers,
    required this.moreMenu,
    required this.tripSettings,
    required this.shareSnapshot,
    required this.closeReport,
    required this.addExpense,
    required this.loadError,
    required this.notFoundTitle,
    required this.notFoundSubtitle,
    required this.totalSpentLabel,
    required this.perPersonLabel,
    required this.recentActivity,
    required this.noRecentActivity,
    required this.quickExpenses,
    required this.quickPlans,
    required this.quickBalances,
    required this.quickMembers,
    required this.quickMemories,
  });

  final String tabOverview;
  final String tabExpenses;
  final String tabCapture;
  final String memoriesTitle;
  final String tabBalances;
  final String tabMembers;
  final String moreMenu;
  final String tripSettings;
  final String shareSnapshot;
  final String closeReport;
  final String addExpense;
  final String loadError;
  final String notFoundTitle;
  final String notFoundSubtitle;
  final String totalSpentLabel;
  final String Function(String amount) perPersonLabel;
  final String recentActivity;
  final String noRecentActivity;
  final String quickExpenses;
  final String quickPlans;
  final String quickBalances;
  final String quickMembers;
  final String quickMemories;
}
