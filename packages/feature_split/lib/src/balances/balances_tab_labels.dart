/// Localized copy for the Balances tab (S27 scan-first hierarchy).
class BalancesTabLabels {
  const BalancesTabLabels({
    required this.loadError,
    required this.whoOwesWhomTitle,
    required this.whoOwesWhomHint,
    required this.paysLine,
    required this.waitingForPayer,
    required this.markAsSettled,
    this.netHeroTitle = 'Net balance',
    this.netHeroSettled = 'Settled',
    this.netHeroYouOwe = 'You owe',
    this.netHeroYouAreOwed = "You're owed",
    this.legendOwedToYou = 'Owed to you',
    this.legendYouOwe = 'You owe',
    this.statusAwaiting = 'Awaiting confirmation',
    this.statusMarkedPaid = 'Marked paid',
    this.settleUp = 'Settle up',
    required this.myActionTitle,
    required this.confirmPaymentsHint,
    required this.confirmPaymentFrom,
    required this.confirm,
    required this.reject,
    required this.awaitingConfirmationTitle,
    required this.awaitingConfirmationHint,
    required this.youToRecipient,
    required this.markedNotConfirmed,
    required this.cancelMark,
    required this.disputedTitle,
    required this.finalTitle,
    required this.netBalanceLine,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.paymentConfirmed,
    required this.markedNotReceived,
    required this.markCancelled,
    required this.someoneFallback,
  });

  final String loadError;
  final String whoOwesWhomTitle;
  final String whoOwesWhomHint;
  final String Function(String from, String to) paysLine;
  final String Function(String name) waitingForPayer;
  final String markAsSettled;
  final String netHeroTitle;
  final String netHeroSettled;
  final String netHeroYouOwe;
  final String netHeroYouAreOwed;
  final String legendOwedToYou;
  final String legendYouOwe;
  final String statusAwaiting;
  final String statusMarkedPaid;
  final String settleUp;
  final String myActionTitle;
  final String confirmPaymentsHint;
  final String Function(String name) confirmPaymentFrom;
  final String confirm;
  final String reject;
  final String awaitingConfirmationTitle;
  final String awaitingConfirmationHint;
  final String Function(String name) youToRecipient;
  final String Function(String amount) markedNotConfirmed;
  final String cancelMark;
  final String disputedTitle;
  final String finalTitle;
  final String Function(String name, bool isOwed, String amount) netBalanceLine;
  final String emptyTitle;
  final String emptySubtitle;
  final String paymentConfirmed;
  final String markedNotReceived;
  final String markCancelled;
  final String someoneFallback;
}
