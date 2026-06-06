// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'Vamo';

  @override
  String get settingsDevLocaleSection => 'Developer — locale preview';

  @override
  String get settingsDevLocaleSystem => 'System default';

  @override
  String get settingsDevLocaleRtl => 'RTL preview (Arabic layout)';

  @override
  String get settingsDevLocalePseudo => 'Pseudo-locale (long strings)';

  @override
  String get navTrips => 'Trips';

  @override
  String get navActivity => 'Activity';

  @override
  String get navExpenses => 'Expenses';

  @override
  String get navProfile => 'Profile';

  @override
  String get tripsTitle => 'Your trips';

  @override
  String get tripsEmptyTitle => 'No trips yet';

  @override
  String get tripsEmptySubtitle => 'Tap + to start one.';

  @override
  String tripsSyncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes waiting to sync',
      one: '1 change waiting to sync',
    );
    return '$_temp0';
  }

  @override
  String get tripsSyncSubtitle => 'Will upload when you are back online';

  @override
  String get tripsFilterAll => 'All';

  @override
  String get tripsFilterUpcoming => 'Upcoming';

  @override
  String get tripsFilterPast => 'Past';

  @override
  String get tripsFilterDrafts => 'Drafts';

  @override
  String get tripsLoadError => 'Could not load your trips.';

  @override
  String get tripsSyncError => 'Could not sync your trips.';

  @override
  String get activityTitle => 'Activity';

  @override
  String get activityEmptyTitle => 'Nothing yet';

  @override
  String get activityEmptySubtitle =>
      'Expenses and settlements will show up here.';

  @override
  String get activityLoadError => 'Could not load activity.';

  @override
  String get expensesTitle => 'Expenses';

  @override
  String get expensesEmptyTitle => 'No trips yet';

  @override
  String get expensesEmptySubtitle => 'Start a trip to track spending.';

  @override
  String get expensesLoadError => 'Could not load expenses.';

  @override
  String get expensesBalanceAllSettled => 'All settled across your trips';

  @override
  String expensesBalanceYouOwe(String amount, int tripCount) {
    String _temp0 = intl.Intl.pluralLogic(
      tripCount,
      locale: localeName,
      other: '$tripCount trips',
      one: '1 trip',
    );
    return 'You owe $amount across $_temp0';
  }

  @override
  String expensesBalanceYouAreOwed(String amount) {
    return 'You\'re owed $amount';
  }

  @override
  String get expensesBalanceAcrossTrips => 'By trip';

  @override
  String get expensesPeriodThisMonth => 'This month';

  @override
  String get expensesPeriodThisYear => 'This year';

  @override
  String get expensesEarlierSection => 'Earlier';

  @override
  String get expensesTotalSpent => 'Total spent';

  @override
  String get expensesMyShare => 'My share';

  @override
  String get expensesSettlementUnsettled => 'Unsettled';

  @override
  String get expensesSettlementSettled => 'Settled';

  @override
  String get expensesSettlementAllSettled => 'All settled';

  @override
  String get expensesUnresolvedBadge => 'Unresolved';

  @override
  String get expensesPickerTitle => 'Add expense to which trip?';

  @override
  String get expensesPickerLastUsed => 'Last used';

  @override
  String get inviteShowQr => 'Show QR';

  @override
  String get inviteScanQr => 'Scan a Vamo QR';

  @override
  String get inviteQrCaption => 'Point a camera at this to join';

  @override
  String get inviteNotVamoQr => 'That\'s not a Vamo invite';

  @override
  String get inviteCameraDenied =>
      'Camera access is needed to scan. Paste the invite link below instead.';

  @override
  String get invitePasteLink => 'Paste invite link';

  @override
  String get invitePasteHint => 'https://vamo.world/j/…';

  @override
  String get invitePasteJoin => 'Join from link';

  @override
  String get inviteScannerTitle => 'Scan invite QR';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileAbout => 'About';

  @override
  String get profileVersion => 'Version';

  @override
  String get profileLicenses => 'Licenses';

  @override
  String get profilePrivacy => 'Privacy policy';

  @override
  String get brandTagline => 'Si va?';

  @override
  String get profilePlusTitle => 'Vamo Plus';

  @override
  String get profilePlusSubtitle => 'Coming soon. Tap to register interest.';

  @override
  String get profileSuggestTitle => 'Suggest a feature';

  @override
  String get profileSuggestSubtitle => 'We read every submission';

  @override
  String get profileAnalytics => 'Analytics';

  @override
  String get profileAnalyticsHint =>
      'PostHog key not set — events log to the debug console.';

  @override
  String get profileSignOut => 'Sign out';

  @override
  String get profileSave => 'Save changes';

  @override
  String get profileSaved => 'Profile saved.';

  @override
  String get profileLoadError => 'Could not load your profile.';

  @override
  String get profileSection => 'Profile';

  @override
  String get profileDisplayName => 'Display name';

  @override
  String get profileDisplayNameHint => 'How Vamigos see you';

  @override
  String get profileDefaultCurrency => 'Default trip currency';

  @override
  String get profileDefaultCurrencyHelper => 'Used when you create a new trip';

  @override
  String get profileBilling => 'Billing';

  @override
  String get profilePlusSheetDescription =>
      'Upgrade anytime; downgrade or cancel at the end of your billing cycle — no dark patterns.';

  @override
  String get profilePosthogActive => 'PostHog is active.';

  @override
  String get authTagline => 'Let\'s go. Together.';

  @override
  String get planTabTitle => 'Plan';

  @override
  String get planEmptyTitle => 'Nothing on the board yet';

  @override
  String get planEmptySubtitle =>
      'Add lodging, transport, or activities for the group.';

  @override
  String get planUndatedSection => 'No date';

  @override
  String get planChecklistsSection => 'Checklists';

  @override
  String get planAddItem => 'Add to plan';

  @override
  String get planAddListItemHint => 'New checklist item';

  @override
  String get planDefaultListName => 'Packing';

  @override
  String get planDeleteItem => 'Delete';

  @override
  String get planEditItem => 'Edit';

  @override
  String get planKindLodging => 'Lodging';

  @override
  String get planKindFlight => 'Flight';

  @override
  String get planKindTrain => 'Train';

  @override
  String get planKindActivity => 'Activity';

  @override
  String get planKindOther => 'Other';

  @override
  String get planSheetTitleAdd => 'Add plan item';

  @override
  String get planSheetTitleEdit => 'Edit plan item';

  @override
  String get planFieldTitle => 'Title';

  @override
  String get planFieldKind => 'Type';

  @override
  String get planFieldNotes => 'Notes';

  @override
  String get planFieldStart => 'Starts';

  @override
  String get planFieldEnd => 'Ends';

  @override
  String get planSave => 'Save';

  @override
  String get planLoadError => 'Could not load the plan.';

  @override
  String get planChecklistsLoadError => 'Could not load checklists.';

  @override
  String get eventRsvpGoing => 'Going';

  @override
  String get eventRsvpMaybe => 'Maybe';

  @override
  String get eventRsvpDeclined => 'Declined';

  @override
  String eventRsvpSummary(int going, int maybe) {
    return '$going going · $maybe maybe';
  }

  @override
  String get planEventRsvpHint =>
      'After you save, you and other Vamigos can RSVP on the plan board.';

  @override
  String get planEventRsvpSection => 'RSVP';

  @override
  String get activityEventCreatedSubtitle => 'Event added';

  @override
  String activityEventRsvpSubtitle(String status) {
    return 'RSVP: $status';
  }

  @override
  String expenseIncludedDisputedBy(String memberName) {
    return 'included — disputed by $memberName';
  }

  @override
  String expenseIncludedPendingFrom(String memberName) {
    return 'included — pending from $memberName';
  }

  @override
  String get expenseSomeoneFallback => 'Someone';

  @override
  String get expenseProposalRowPrefix => 'Proposal';

  @override
  String get expenseProposalNotInBalances =>
      'Proposal — not in balances until committed';

  @override
  String get expenseShareAccepted => 'Accepted';

  @override
  String get expenseYourShare => 'Your share';

  @override
  String get expenseDispute => 'Dispute';

  @override
  String get expenseAccept => 'Accept';

  @override
  String get expenseCommitToBalances => 'Commit to balances';

  @override
  String get expenseVoidProposal => 'Void proposal';

  @override
  String get expenseDisputeReasonTitle => 'Why are you disputing?';

  @override
  String get expenseDisputeReasonHint => 'Reason';

  @override
  String get expenseGovernanceCancel => 'Cancel';

  @override
  String get expenseGovernanceSubmit => 'Submit';

  @override
  String get expenseProposeCostAction => 'Propose a cost';

  @override
  String get expenseAddTitle => 'Add expense';

  @override
  String get expenseProposeCostTitle => 'Propose a cost';

  @override
  String get expenseSaveExpense => 'Save expense';

  @override
  String get expenseSaveProposal => 'Save proposal';

  @override
  String expenseTripBalancesIn(String currency) {
    return 'Trip balances in $currency';
  }

  @override
  String expenseSplitEqual(int count) {
    return 'Split equally · $count Vamigos';
  }

  @override
  String get expenseSplitSolo => 'All on you (solo)';

  @override
  String get tripSettingsTitle => 'Trip settings';

  @override
  String get tripBudgetSectionTitle => 'Budget';

  @override
  String get tripBudgetModeNone => 'No budget';

  @override
  String get tripBudgetModeInformational => 'Informational burn-down';

  @override
  String get tripBudgetModeFormal => 'Formal (over-budget flag)';

  @override
  String get tripBudgetAmountLabel => 'Budget amount';

  @override
  String get tripBudgetSave => 'Save budget';

  @override
  String tripBudgetRemaining(String amount, String currency) {
    return '$amount left in $currency';
  }

  @override
  String tripBudgetOver(String currency) {
    return 'Over budget ($currency)';
  }

  @override
  String get tripFxSectionTitle => 'Trip exchange rates';

  @override
  String get tripFxAddCurrency => 'Add currency';

  @override
  String get tripFxRefresh => 'Refresh rate';

  @override
  String tripFxCapturedAt(String capturedAt) {
    return 'Captured $capturedAt';
  }

  @override
  String get tripFxSource => 'Source';

  @override
  String get tripFxRateReadOnly =>
      'Rates are captured from the market — not editable';

  @override
  String get tripOverBudgetCommitTitle => 'Commit over budget?';

  @override
  String get tripOverBudgetCommitBody =>
      'This commit would exceed the formal trip budget. You can still proceed after confirming.';

  @override
  String tripOverBudgetConfirmHint(String phrase) {
    return 'Type $phrase to confirm';
  }

  @override
  String get tripOverBudgetConfirmPhrase => 'OVER BUDGET';

  @override
  String get tripBudgetConfirm => 'Confirm';

  @override
  String get tripBudgetCancel => 'Cancel';

  @override
  String get tripCurrencyMissingAdmin =>
      'Ask an admin to add this currency in trip settings';

  @override
  String get tripLifecycleMarkDone => 'I\'m done';

  @override
  String get tripLifecycleRequestClose => 'Request close';

  @override
  String get tripLifecycleCancelTrip => 'Cancel trip';

  @override
  String get tripLifecycleAcceptClose => 'Accept close';

  @override
  String get tripLifecycleObject => 'Object…';

  @override
  String get tripLifecycleWithdrawObjection => 'Withdraw objection';

  @override
  String get tripLifecycleCloseAnyway => 'Close anyway';

  @override
  String get tripLifecycleCancelledBanner =>
      'Trip cancelled — no further activity.';

  @override
  String get tripLifecycleClosedBanner => 'Trip closed — settling still open.';

  @override
  String get tripLifecycleClosingGeneric =>
      'Trip is closing — review balances and respond.';

  @override
  String tripLifecycleClosingCountdown(int days) {
    return 'Trip closes in $days days unless someone objects.';
  }

  @override
  String get tripLifecycleObjectionNotice =>
      'A member objected to closing — discuss or owner may close anyway.';

  @override
  String get tripLifecycleMarkDoneTitle => 'Mark yourself done?';

  @override
  String get tripLifecycleMarkDoneBody =>
      'You can still log expenses until the trip closes. When everyone is done, the close review starts.';

  @override
  String get tripLifecycleMarkDoneConfirm => 'I\'m done';

  @override
  String get tripLifecycleNotYet => 'Not yet';

  @override
  String get tripLifecycleCancelTitle => 'Cancel this trip?';

  @override
  String get tripLifecycleCancelBody =>
      'Only possible before the start date. Members will be notified.';

  @override
  String get tripLifecycleKeepTrip => 'Keep';

  @override
  String get tripLifecycleRequestCloseTitle => 'Request trip close?';

  @override
  String get tripLifecycleRequestCloseBody =>
      'Members get 14 days to review balances and accept or object. You can still log expenses during the review.';

  @override
  String get tripLifecycleRequestCloseConfirm => 'Request close';

  @override
  String get tripLifecycleTripActions => 'Trip actions';

  @override
  String get tripLifecycleCloseAnywayTitle => 'Close anyway?';

  @override
  String get tripLifecycleCloseAnywayBody =>
      'An objection is on record. Force-close keeps it visible in the close report.';

  @override
  String get tripLifecycleCloseAnywayHint => 'Type CLOSE to confirm';

  @override
  String get tripLifecycleCloseAnywayPhrase => 'CLOSE';

  @override
  String get tripLifecycleCloseTrip => 'Close trip';

  @override
  String get tripLifecycleBack => 'Back';

  @override
  String get tripLifecycleObjectTitle => 'Object to closing';

  @override
  String get tripLifecycleObjectReasonLabel => 'Reason (required)';

  @override
  String get tripLifecycleObjectReasonHint => 'What still needs resolving?';

  @override
  String get tripLifecycleSubmitObjection => 'Submit objection';
}
