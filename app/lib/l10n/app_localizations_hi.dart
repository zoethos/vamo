// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

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
  String get expensesEmptyTitle => 'No expenses yet';

  @override
  String get expensesEmptySubtitle => 'Add one from a trip or tap +.';

  @override
  String get expensesLoadError => 'Could not load expenses.';

  @override
  String get expensesAllTrips => 'All trips';

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
  String get authTagline => 'Let\'s go. Together.';
}
