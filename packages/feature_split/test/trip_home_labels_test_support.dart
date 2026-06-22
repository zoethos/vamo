import 'package:feature_split/src/balances/balances_tab_labels.dart';
import 'package:feature_split/src/trips/trip_home_labels.dart';

TripHomeLabels tripHomeLabelsTestDefaults() => const TripHomeLabels(
      tabOverview: 'Overview',
      tabExpenses: 'Expenses',
      tabCapture: 'Capture',
      memoriesTitle: 'Memories',
      tabBalances: 'Balances',
      tabMembers: 'Members',
      moreMenu: 'More',
      tripSettings: 'Trip settings',
      shareSnapshot: 'Share snapshot',
      closeReport: 'Close report',
      addExpense: 'Add expense',
      loadError: 'Could not load this trip.',
      notFoundTitle: 'Trip not found',
      notFoundSubtitle: 'It may have been removed or you no longer have access.',
      totalSpentLabel: 'Total Spent',
      perPersonLabel: _perPerson,
      recentActivity: 'Recent activity',
      noRecentActivity: 'No expenses yet.',
      quickExpenses: 'Expenses',
      quickPlans: 'Plans',
      quickBalances: 'Balances',
      quickMembers: 'Members',
      quickMemories: 'Memories',
    );

const testTripHomeLabels = TripHomeLabels(
  tabOverview: 'Overview',
  tabExpenses: 'Expenses',
  tabCapture: 'Capture',
  memoriesTitle: 'Memories',
  tabBalances: 'Balances',
  tabMembers: 'Members',
  moreMenu: 'More',
  tripSettings: 'Trip settings',
  shareSnapshot: 'Share snapshot',
  closeReport: 'Close report',
  addExpense: 'Add expense',
  loadError: 'Could not load this trip.',
  notFoundTitle: 'Trip not found',
  notFoundSubtitle: 'It may have been removed or you no longer have access.',
  totalSpentLabel: 'Total Spent',
  perPersonLabel: _perPerson,
  recentActivity: 'Recent activity',
  noRecentActivity: 'No expenses yet.',
  quickExpenses: 'Expenses',
  quickPlans: 'Plans',
  quickBalances: 'Balances',
  quickMembers: 'Members',
  quickMemories: 'Memories',
);

String _perPerson(String amount) => 'Per person $amount';

final testBalancesTabLabels = BalancesTabLabels(
  loadError: 'Could not load balances.',
  whoOwesWhomTitle: 'Who owes whom',
  whoOwesWhomHint: 'Fewest payments to clear the trip.',
  paysLine: _paysLine,
  waitingForPayer: _waitingForPayer,
  markAsSettled: 'Mark as settled',
  legendOwedToYou: 'Owed to you',
  legendYouOwe: 'You owe',
  statusAwaiting: 'Awaiting confirmation',
  statusMarkedPaid: 'Marked paid',
  myActionTitle: 'Your action',
  confirmPaymentsHint: 'Confirm payments hint',
  confirmPaymentFrom: _confirmFrom,
  confirm: 'Confirm',
  reject: 'Reject',
  awaitingConfirmationTitle: 'Awaiting confirmation',
  awaitingConfirmationHint: 'Awaiting hint',
  youToRecipient: _youTo,
  markedNotConfirmed: _markedNotConfirmed,
  cancelMark: 'Cancel',
  disputedTitle: "What's disputed",
  finalTitle: "What's final",
  netBalanceLine: _netLine,
  emptyTitle: 'All square',
  emptySubtitle: 'No open debts',
  paymentConfirmed: 'Payment confirmed.',
  markedNotReceived: 'Marked as not received.',
  markCancelled: 'Mark cancelled',
  someoneFallback: 'Someone',
);

String _paysLine(String from, String to) => '$from pays $to';
String _waitingForPayer(String name) => 'Waiting for $name to pay';
String _confirmFrom(String name) => '$name says they paid you';
String _youTo(String name) => 'You → $name';
String _markedNotConfirmed(String amount) => '$amount · marked, not confirmed';
String _netLine(String name, bool isOwed, String amount) =>
    '$name ${isOwed ? 'is owed' : 'owes'} $amount';
