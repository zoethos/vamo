// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

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
}
