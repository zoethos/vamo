// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Vamo';

  @override
  String get settingsDevLocaleSection => 'Sviluppatore — anteprima lingua';

  @override
  String get settingsDevLocaleSystem => 'Predefinito di sistema';

  @override
  String get settingsDevLocaleRtl => 'Anteprima RTL (layout arabo)';

  @override
  String get settingsDevLocalePseudo => 'Pseudo-locale (stringhe lunghe)';

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
  String get tripsEmptyUpcomingTitle => 'No upcoming trips';

  @override
  String get tripsEmptyPastTitle => 'No past trips';

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
  String get tripsSectionUpcoming => 'Upcoming';

  @override
  String get tripsSectionPast => 'Past';

  @override
  String tripsParticipants(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Vamigos',
      one: '1 Vamigo',
    );
    return '$_temp0';
  }

  @override
  String get tripsNotificationsTooltip => 'Notifications';

  @override
  String get tripsCreateTripTooltip => 'Create trip';

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
  String get inviteVamigos => 'Invite Vamigos';

  @override
  String get inviteShareJoinLink => 'Share a join link';

  @override
  String get inviteFromContacts => 'Invite from contacts';

  @override
  String get inviteContactMethodTextMessage => 'Text message';

  @override
  String get inviteContactMethodEmail => 'Email';

  @override
  String get inviteContactMethodShareLink => 'Share link';

  @override
  String get inviteContactSubject => 'Join my Vamo trip';

  @override
  String inviteContactBody(String webUrl, String appUri) {
    return 'Join my trip on Vamo!\n$webUrl\n\nHave the app? Tap: $appUri';
  }

  @override
  String get membersVamigosTitle => 'Vamigos';

  @override
  String get membersInviteHintSolo =>
      'Invite friends — balances unlock at 2+ people.';

  @override
  String membersCountOnTrip(int count) {
    return '$count on this trip';
  }

  @override
  String get membersShareFootnote =>
      'Share a link — they can join mid-trip. Opens Vamo or the store.';

  @override
  String get membersMakeCoAdmin => 'Make co-admin';

  @override
  String get membersRemoveCoAdmin => 'Remove co-admin';

  @override
  String get inviteAction => 'Invite';

  @override
  String get tripHomeTabOverview => 'Overview';

  @override
  String get tripHomeTabExpenses => 'Expenses';

  @override
  String get tripHomeTabCapture => 'Capture';

  @override
  String get tripHomeMemories => 'Memories';

  @override
  String get tripHomeTabBalances => 'Balances';

  @override
  String get tripHomeTabMembers => 'Members';

  @override
  String get tripHomeMoreMenu => 'More';

  @override
  String get tripHomeSettings => 'Trip settings';

  @override
  String get tripHomeShareSnapshot => 'Share snapshot';

  @override
  String get tripHomeAddExpense => 'Add expense';

  @override
  String get tripHomeLoadError => 'Could not load this trip.';

  @override
  String get tripHomeNotFoundTitle => 'Trip not found';

  @override
  String get tripHomeNotFoundSubtitle =>
      'It may have been removed or you no longer have access.';

  @override
  String get tripHomeTotalSpent => 'Total Spent';

  @override
  String tripHomePerPerson(String amount) {
    return 'Per person $amount';
  }

  @override
  String get tripHomeRecentActivity => 'Recent activity';

  @override
  String get tripHomeNoRecentActivity => 'No expenses yet.';

  @override
  String get tripHomeQuickExpenses => 'Expenses';

  @override
  String get tripHomeQuickPlans => 'Plans';

  @override
  String get tripHomeQuickBalances => 'Balances';

  @override
  String get tripHomeQuickMembers => 'Members';

  @override
  String get tripHomeQuickMemories => 'Memories';

  @override
  String get balancesLoadError => 'Could not load balances.';

  @override
  String get balancesWhoOwesTitle => 'Who owes whom';

  @override
  String get balancesWhoOwesHint => 'Fewest payments to clear the trip.';

  @override
  String balancesPaysLine(String from, String to) {
    return '$from pays $to';
  }

  @override
  String balancesWaitingForPayer(String name) {
    return 'Waiting for $name to pay';
  }

  @override
  String get balancesMarkSettled => 'Mark as settled';

  @override
  String get balancesMyActionTitle => 'Your action';

  @override
  String get balancesConfirmHint =>
      'Marked as paid — confirm if you received it, or reject if not.';

  @override
  String balancesConfirmFrom(String name) {
    return '$name says they paid you';
  }

  @override
  String get balancesConfirm => 'Confirm';

  @override
  String get balancesReject => 'Reject';

  @override
  String get balancesAwaitingTitle => 'Awaiting confirmation';

  @override
  String get balancesAwaitingHint =>
      'You marked these paid — recipients can confirm or reject. Cancel if you did not actually pay.';

  @override
  String balancesYouToRecipient(String name) {
    return 'You → $name';
  }

  @override
  String balancesMarkedNotConfirmed(String amount) {
    return '$amount · marked, not confirmed';
  }

  @override
  String get balancesCancelMark => 'Cancel';

  @override
  String get balancesDisputedTitle => 'What\'s disputed';

  @override
  String get balancesFinalTitle => 'What\'s final';

  @override
  String balancesNetLine(String name, String direction, String amount) {
    return '$name $direction $amount';
  }

  @override
  String get balancesNetOwed => 'is owed';

  @override
  String get balancesNetOwes => 'owes';

  @override
  String get balancesEmptyTitle => 'All square';

  @override
  String get balancesEmptySubtitle =>
      'No open debts — add expenses or invite Vamigos.';

  @override
  String get balancesPaymentConfirmed => 'Payment confirmed.';

  @override
  String get balancesMarkedNotReceived => 'Marked as not received.';

  @override
  String get balancesMarkCancelled =>
      'Mark cancelled — debt is back on your balance.';

  @override
  String get authContinueEmail => 'Continue with email';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authEmailHint => 'you@example.com';

  @override
  String get authOtpLabel => '6-digit code';

  @override
  String authCodeSent(String email) {
    return 'We sent a code to $email';
  }

  @override
  String get authVerifyContinue => 'Verify & continue';

  @override
  String get authDifferentEmail => 'Use a different email';

  @override
  String get authOrDivider => 'or';

  @override
  String get authContinueApple => 'Continue with Apple';

  @override
  String get authContinueGoogle => 'Continue with Google';

  @override
  String get authResendCode => 'Send me a new code';

  @override
  String authResendCodeCooldown(int seconds) {
    return 'Send me a new code (${seconds}s)';
  }

  @override
  String get createTripTitle => 'New trip';

  @override
  String get createTripHeadline => 'Si va?';

  @override
  String get createTripSubtitle => 'Start solo — you can invite Vamigos later.';

  @override
  String get createTripNameLabel => 'Trip name';

  @override
  String get createTripNameHint => 'Amalfi with the crew';

  @override
  String get createTripNameRequired => 'Give your trip a name';

  @override
  String get createTripDestinationLabel => 'Destination (optional)';

  @override
  String get createTripDestinationHint => 'Positano, Italy';

  @override
  String get createTripCurrencyLabel => 'Base currency';

  @override
  String get createTripStartDate => 'Start date';

  @override
  String get createTripEndDate => 'End date';

  @override
  String get createTripSubmit => 'Create trip';

  @override
  String get createTripEndBeforeStart =>
      'End date must be on or after start date.';

  @override
  String get createTripClearDate => 'Clear date';

  @override
  String get datePickerCancel => 'Cancel';

  @override
  String get datePickerSkip => 'Skip';

  @override
  String get datePickerSelect => 'Select';

  @override
  String get addExpenseTitle => 'Add expense';

  @override
  String get addExpenseTripNotFound => 'Trip not found';

  @override
  String get addExpenseScanReceipt => 'Scan receipt';

  @override
  String get addExpenseTakePhoto => 'Take photo';

  @override
  String get addExpenseChooseGallery => 'Choose from gallery';

  @override
  String get addExpenseChoosePayer => 'Choose who paid.';

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
  String get profileAppearanceSection => 'Appearance';

  @override
  String get profileAppearanceLight => 'Light';

  @override
  String get profileAppearanceDark => 'Dark';

  @override
  String get profileAppearanceSystem => 'System';

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
  String get planAddChecklistItem => 'Add checklist item';

  @override
  String get planDeleteConfirmTitle => 'Delete this item?';

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
  String get planEndBeforeStart => 'End must be on or after start.';

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
  String eventRsvpSummary(int going, int maybe, int declined) {
    return '$going going · $maybe maybe · $declined declined';
  }

  @override
  String get planEventRsvpHint =>
      'After you save, you and other Vamigos can RSVP on the plan board.';

  @override
  String get planEventRsvpSection => 'RSVP';

  @override
  String get eventRsvpUpdateFailed => 'Could not update RSVP. Try again.';

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
