import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_he.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('en', 'XA'),
    Locale('he'),
    Locale('hi'),
    Locale('it'),
    Locale('ja'),
    Locale('ru'),
    Locale('zh')
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'Vamo'**
  String get appTitle;

  /// No description provided for @settingsDevLocaleSection.
  ///
  /// In en, this message translates to:
  /// **'Developer — locale preview'**
  String get settingsDevLocaleSection;

  /// No description provided for @settingsDevLocaleSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsDevLocaleSystem;

  /// No description provided for @settingsDevLocaleRtl.
  ///
  /// In en, this message translates to:
  /// **'RTL preview (Arabic layout)'**
  String get settingsDevLocaleRtl;

  /// No description provided for @settingsDevLocalePseudo.
  ///
  /// In en, this message translates to:
  /// **'Pseudo-locale (long strings)'**
  String get settingsDevLocalePseudo;

  /// No description provided for @navTrips.
  ///
  /// In en, this message translates to:
  /// **'Trips'**
  String get navTrips;

  /// No description provided for @navActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get navActivity;

  /// No description provided for @navExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get navExpenses;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @tripsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your trips'**
  String get tripsTitle;

  /// No description provided for @tripsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No trips yet'**
  String get tripsEmptyTitle;

  /// No description provided for @tripsEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap + to start one.'**
  String get tripsEmptySubtitle;

  /// No description provided for @tripsSyncPending.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change waiting to sync} other{{count} changes waiting to sync}}'**
  String tripsSyncPending(int count);

  /// No description provided for @tripsSyncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Will upload when you are back online'**
  String get tripsSyncSubtitle;

  /// No description provided for @tripsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tripsFilterAll;

  /// No description provided for @tripsFilterUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get tripsFilterUpcoming;

  /// No description provided for @tripsFilterPast.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get tripsFilterPast;

  /// No description provided for @tripsFilterDrafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get tripsFilterDrafts;

  /// No description provided for @tripsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your trips.'**
  String get tripsLoadError;

  /// No description provided for @tripsSyncError.
  ///
  /// In en, this message translates to:
  /// **'Could not sync your trips.'**
  String get tripsSyncError;

  /// No description provided for @activityTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activityTitle;

  /// No description provided for @activityEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get activityEmptyTitle;

  /// No description provided for @activityEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Expenses and settlements will show up here.'**
  String get activityEmptySubtitle;

  /// No description provided for @activityLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load activity.'**
  String get activityLoadError;

  /// No description provided for @expensesTitle.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expensesTitle;

  /// No description provided for @expensesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No expenses yet'**
  String get expensesEmptyTitle;

  /// No description provided for @expensesEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add one from a trip or tap +.'**
  String get expensesEmptySubtitle;

  /// No description provided for @expensesLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load expenses.'**
  String get expensesLoadError;

  /// No description provided for @expensesAllTrips.
  ///
  /// In en, this message translates to:
  /// **'All trips'**
  String get expensesAllTrips;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get profileAbout;

  /// No description provided for @profileVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get profileVersion;

  /// No description provided for @profileLicenses.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get profileLicenses;

  /// No description provided for @profilePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get profilePrivacy;

  /// No description provided for @brandTagline.
  ///
  /// In en, this message translates to:
  /// **'Si va?'**
  String get brandTagline;

  /// No description provided for @profilePlusTitle.
  ///
  /// In en, this message translates to:
  /// **'Vamo Plus'**
  String get profilePlusTitle;

  /// No description provided for @profilePlusSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Coming soon. Tap to register interest.'**
  String get profilePlusSubtitle;

  /// No description provided for @profileSuggestTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggest a feature'**
  String get profileSuggestTitle;

  /// No description provided for @profileSuggestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We read every submission'**
  String get profileSuggestSubtitle;

  /// No description provided for @profileAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get profileAnalytics;

  /// No description provided for @profileAnalyticsHint.
  ///
  /// In en, this message translates to:
  /// **'PostHog key not set — events log to the debug console.'**
  String get profileAnalyticsHint;

  /// No description provided for @profileSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get profileSignOut;

  /// No description provided for @profileSave.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get profileSave;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved.'**
  String get profileSaved;

  /// No description provided for @profileLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your profile.'**
  String get profileLoadError;

  /// No description provided for @profileSection.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileSection;

  /// No description provided for @profileDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get profileDisplayName;

  /// No description provided for @profileDisplayNameHint.
  ///
  /// In en, this message translates to:
  /// **'How Vamigos see you'**
  String get profileDisplayNameHint;

  /// No description provided for @profileDefaultCurrency.
  ///
  /// In en, this message translates to:
  /// **'Default trip currency'**
  String get profileDefaultCurrency;

  /// No description provided for @profileDefaultCurrencyHelper.
  ///
  /// In en, this message translates to:
  /// **'Used when you create a new trip'**
  String get profileDefaultCurrencyHelper;

  /// No description provided for @profileBilling.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get profileBilling;

  /// No description provided for @profilePlusSheetDescription.
  ///
  /// In en, this message translates to:
  /// **'Upgrade anytime; downgrade or cancel at the end of your billing cycle — no dark patterns.'**
  String get profilePlusSheetDescription;

  /// No description provided for @profilePosthogActive.
  ///
  /// In en, this message translates to:
  /// **'PostHog is active.'**
  String get profilePosthogActive;

  /// No description provided for @authTagline.
  ///
  /// In en, this message translates to:
  /// **'Let\'s go. Together.'**
  String get authTagline;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ar',
        'en',
        'he',
        'hi',
        'it',
        'ja',
        'ru',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'en':
      {
        switch (locale.countryCode) {
          case 'XA':
            return AppLocalizationsEnXa();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'he':
      return AppLocalizationsHe();
    case 'hi':
      return AppLocalizationsHi();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
