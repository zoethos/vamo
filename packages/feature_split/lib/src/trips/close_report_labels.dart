/// Localized copy for the close report screen (S22).
class CloseReportLabels {
  const CloseReportLabels({
    required this.title,
    required this.loadError,
    required this.notAvailable,
    required this.balancesTitle,
    required this.membersTitle,
    required this.disputedTitle,
    required this.consentAccepted,
    required this.consentObjected,
    required this.consentDeemed,
    required this.consentPending,
    required this.consentNotNotified,
    required this.balanceLine,
    required this.noBalances,
  });

  final String title;
  final String loadError;
  final String notAvailable;
  final String balancesTitle;
  final String membersTitle;
  final String disputedTitle;
  final String consentAccepted;
  final String consentObjected;
  final String consentDeemed;
  final String consentPending;
  final String consentNotNotified;
  final String Function(String name, bool isOwed, String amount) balanceLine;
  final String noBalances;
}
