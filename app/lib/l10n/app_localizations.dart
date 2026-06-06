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
  /// **'No trips yet'**
  String get expensesEmptyTitle;

  /// No description provided for @expensesEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start a trip to track spending.'**
  String get expensesEmptySubtitle;

  /// No description provided for @expensesLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load expenses.'**
  String get expensesLoadError;

  /// No description provided for @expensesBalanceAllSettled.
  ///
  /// In en, this message translates to:
  /// **'All settled across your trips'**
  String get expensesBalanceAllSettled;

  /// No description provided for @expensesBalanceYouOwe.
  ///
  /// In en, this message translates to:
  /// **'You owe {amount} across {tripCount, plural, =1{1 trip} other{{tripCount} trips}}'**
  String expensesBalanceYouOwe(String amount, int tripCount);

  /// No description provided for @expensesBalanceYouAreOwed.
  ///
  /// In en, this message translates to:
  /// **'You\'re owed {amount}'**
  String expensesBalanceYouAreOwed(String amount);

  /// No description provided for @expensesBalanceAcrossTrips.
  ///
  /// In en, this message translates to:
  /// **'By trip'**
  String get expensesBalanceAcrossTrips;

  /// No description provided for @expensesPeriodThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get expensesPeriodThisMonth;

  /// No description provided for @expensesPeriodThisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get expensesPeriodThisYear;

  /// No description provided for @expensesEarlierSection.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get expensesEarlierSection;

  /// No description provided for @expensesTotalSpent.
  ///
  /// In en, this message translates to:
  /// **'Total spent'**
  String get expensesTotalSpent;

  /// No description provided for @expensesMyShare.
  ///
  /// In en, this message translates to:
  /// **'My share'**
  String get expensesMyShare;

  /// No description provided for @expensesSettlementUnsettled.
  ///
  /// In en, this message translates to:
  /// **'Unsettled'**
  String get expensesSettlementUnsettled;

  /// No description provided for @expensesSettlementSettled.
  ///
  /// In en, this message translates to:
  /// **'Settled'**
  String get expensesSettlementSettled;

  /// No description provided for @expensesSettlementAllSettled.
  ///
  /// In en, this message translates to:
  /// **'All settled'**
  String get expensesSettlementAllSettled;

  /// No description provided for @expensesUnresolvedBadge.
  ///
  /// In en, this message translates to:
  /// **'Unresolved'**
  String get expensesUnresolvedBadge;

  /// No description provided for @expensesPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add expense to which trip?'**
  String get expensesPickerTitle;

  /// No description provided for @expensesPickerLastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last used'**
  String get expensesPickerLastUsed;

  /// No description provided for @inviteShowQr.
  ///
  /// In en, this message translates to:
  /// **'Show QR'**
  String get inviteShowQr;

  /// No description provided for @inviteScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan a Vamo QR'**
  String get inviteScanQr;

  /// No description provided for @inviteQrCaption.
  ///
  /// In en, this message translates to:
  /// **'Point a camera at this to join'**
  String get inviteQrCaption;

  /// No description provided for @inviteNotVamoQr.
  ///
  /// In en, this message translates to:
  /// **'That\'s not a Vamo invite'**
  String get inviteNotVamoQr;

  /// No description provided for @inviteCameraDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera access is needed to scan. Paste the invite link below instead.'**
  String get inviteCameraDenied;

  /// No description provided for @invitePasteLink.
  ///
  /// In en, this message translates to:
  /// **'Paste invite link'**
  String get invitePasteLink;

  /// No description provided for @invitePasteHint.
  ///
  /// In en, this message translates to:
  /// **'https://vamo.world/j/…'**
  String get invitePasteHint;

  /// No description provided for @invitePasteJoin.
  ///
  /// In en, this message translates to:
  /// **'Join from link'**
  String get invitePasteJoin;

  /// No description provided for @inviteScannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan invite QR'**
  String get inviteScannerTitle;

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

  /// No description provided for @planTabTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get planTabTitle;

  /// No description provided for @planEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing on the board yet'**
  String get planEmptyTitle;

  /// No description provided for @planEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add lodging, transport, or activities for the group.'**
  String get planEmptySubtitle;

  /// No description provided for @planUndatedSection.
  ///
  /// In en, this message translates to:
  /// **'No date'**
  String get planUndatedSection;

  /// No description provided for @planChecklistsSection.
  ///
  /// In en, this message translates to:
  /// **'Checklists'**
  String get planChecklistsSection;

  /// No description provided for @planAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add to plan'**
  String get planAddItem;

  /// No description provided for @planAddListItemHint.
  ///
  /// In en, this message translates to:
  /// **'New checklist item'**
  String get planAddListItemHint;

  /// No description provided for @planDefaultListName.
  ///
  /// In en, this message translates to:
  /// **'Packing'**
  String get planDefaultListName;

  /// No description provided for @planDeleteItem.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get planDeleteItem;

  /// No description provided for @planEditItem.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get planEditItem;

  /// No description provided for @planKindLodging.
  ///
  /// In en, this message translates to:
  /// **'Lodging'**
  String get planKindLodging;

  /// No description provided for @planKindFlight.
  ///
  /// In en, this message translates to:
  /// **'Flight'**
  String get planKindFlight;

  /// No description provided for @planKindTrain.
  ///
  /// In en, this message translates to:
  /// **'Train'**
  String get planKindTrain;

  /// No description provided for @planKindActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get planKindActivity;

  /// No description provided for @planKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get planKindOther;

  /// No description provided for @planSheetTitleAdd.
  ///
  /// In en, this message translates to:
  /// **'Add plan item'**
  String get planSheetTitleAdd;

  /// No description provided for @planSheetTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit plan item'**
  String get planSheetTitleEdit;

  /// No description provided for @planFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get planFieldTitle;

  /// No description provided for @planFieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get planFieldNotes;

  /// No description provided for @planFieldStart.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get planFieldStart;

  /// No description provided for @planFieldEnd.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get planFieldEnd;

  /// No description provided for @planSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get planSave;

  /// No description provided for @planLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load the plan.'**
  String get planLoadError;

  /// No description provided for @planChecklistsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load checklists.'**
  String get planChecklistsLoadError;

  /// No description provided for @expenseIncludedDisputedBy.
  ///
  /// In en, this message translates to:
  /// **'included — disputed by {memberName}'**
  String expenseIncludedDisputedBy(String memberName);

  /// No description provided for @expenseIncludedPendingFrom.
  ///
  /// In en, this message translates to:
  /// **'included — pending from {memberName}'**
  String expenseIncludedPendingFrom(String memberName);

  /// No description provided for @expenseSomeoneFallback.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get expenseSomeoneFallback;

  /// No description provided for @expenseProposalRowPrefix.
  ///
  /// In en, this message translates to:
  /// **'Proposal'**
  String get expenseProposalRowPrefix;

  /// No description provided for @expenseProposalNotInBalances.
  ///
  /// In en, this message translates to:
  /// **'Proposal — not in balances until committed'**
  String get expenseProposalNotInBalances;

  /// No description provided for @expenseShareAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get expenseShareAccepted;

  /// No description provided for @expenseYourShare.
  ///
  /// In en, this message translates to:
  /// **'Your share'**
  String get expenseYourShare;

  /// No description provided for @expenseDispute.
  ///
  /// In en, this message translates to:
  /// **'Dispute'**
  String get expenseDispute;

  /// No description provided for @expenseAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get expenseAccept;

  /// No description provided for @expenseCommitToBalances.
  ///
  /// In en, this message translates to:
  /// **'Commit to balances'**
  String get expenseCommitToBalances;

  /// No description provided for @expenseVoidProposal.
  ///
  /// In en, this message translates to:
  /// **'Void proposal'**
  String get expenseVoidProposal;

  /// No description provided for @expenseDisputeReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Why are you disputing?'**
  String get expenseDisputeReasonTitle;

  /// No description provided for @expenseDisputeReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get expenseDisputeReasonHint;

  /// No description provided for @expenseGovernanceCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get expenseGovernanceCancel;

  /// No description provided for @expenseGovernanceSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get expenseGovernanceSubmit;

  /// No description provided for @expenseProposeCostAction.
  ///
  /// In en, this message translates to:
  /// **'Propose a cost'**
  String get expenseProposeCostAction;

  /// No description provided for @expenseAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get expenseAddTitle;

  /// No description provided for @expenseProposeCostTitle.
  ///
  /// In en, this message translates to:
  /// **'Propose a cost'**
  String get expenseProposeCostTitle;

  /// No description provided for @expenseSaveExpense.
  ///
  /// In en, this message translates to:
  /// **'Save expense'**
  String get expenseSaveExpense;

  /// No description provided for @expenseSaveProposal.
  ///
  /// In en, this message translates to:
  /// **'Save proposal'**
  String get expenseSaveProposal;

  /// No description provided for @expenseTripBalancesIn.
  ///
  /// In en, this message translates to:
  /// **'Trip balances in {currency}'**
  String expenseTripBalancesIn(String currency);

  /// No description provided for @expenseSplitEqual.
  ///
  /// In en, this message translates to:
  /// **'Split equally · {count} Vamigos'**
  String expenseSplitEqual(int count);

  /// No description provided for @expenseSplitSolo.
  ///
  /// In en, this message translates to:
  /// **'All on you (solo)'**
  String get expenseSplitSolo;

  /// No description provided for @tripSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip settings'**
  String get tripSettingsTitle;

  /// No description provided for @tripBudgetSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get tripBudgetSectionTitle;

  /// No description provided for @tripBudgetModeNone.
  ///
  /// In en, this message translates to:
  /// **'No budget'**
  String get tripBudgetModeNone;

  /// No description provided for @tripBudgetModeInformational.
  ///
  /// In en, this message translates to:
  /// **'Informational burn-down'**
  String get tripBudgetModeInformational;

  /// No description provided for @tripBudgetModeFormal.
  ///
  /// In en, this message translates to:
  /// **'Formal (over-budget flag)'**
  String get tripBudgetModeFormal;

  /// No description provided for @tripBudgetAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Budget amount'**
  String get tripBudgetAmountLabel;

  /// No description provided for @tripBudgetSave.
  ///
  /// In en, this message translates to:
  /// **'Save budget'**
  String get tripBudgetSave;

  /// No description provided for @tripBudgetRemaining.
  ///
  /// In en, this message translates to:
  /// **'{amount} left in {currency}'**
  String tripBudgetRemaining(String amount, String currency);

  /// No description provided for @tripBudgetOver.
  ///
  /// In en, this message translates to:
  /// **'Over budget ({currency})'**
  String tripBudgetOver(String currency);

  /// No description provided for @tripFxSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip exchange rates'**
  String get tripFxSectionTitle;

  /// No description provided for @tripFxAddCurrency.
  ///
  /// In en, this message translates to:
  /// **'Add currency'**
  String get tripFxAddCurrency;

  /// No description provided for @tripFxRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh rate'**
  String get tripFxRefresh;

  /// No description provided for @tripFxCapturedAt.
  ///
  /// In en, this message translates to:
  /// **'Captured {capturedAt}'**
  String tripFxCapturedAt(String capturedAt);

  /// No description provided for @tripFxSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get tripFxSource;

  /// No description provided for @tripFxRateReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Rates are captured from the market — not editable'**
  String get tripFxRateReadOnly;

  /// No description provided for @tripOverBudgetCommitTitle.
  ///
  /// In en, this message translates to:
  /// **'Commit over budget?'**
  String get tripOverBudgetCommitTitle;

  /// No description provided for @tripOverBudgetCommitBody.
  ///
  /// In en, this message translates to:
  /// **'This commit would exceed the formal trip budget. You can still proceed after confirming.'**
  String get tripOverBudgetCommitBody;

  /// No description provided for @tripOverBudgetConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Type {phrase} to confirm'**
  String tripOverBudgetConfirmHint(String phrase);

  /// No description provided for @tripOverBudgetConfirmPhrase.
  ///
  /// In en, this message translates to:
  /// **'OVER BUDGET'**
  String get tripOverBudgetConfirmPhrase;

  /// No description provided for @tripBudgetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get tripBudgetConfirm;

  /// No description provided for @tripBudgetCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get tripBudgetCancel;

  /// No description provided for @tripCurrencyMissingAdmin.
  ///
  /// In en, this message translates to:
  /// **'Ask an admin to add this currency in trip settings'**
  String get tripCurrencyMissingAdmin;
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
