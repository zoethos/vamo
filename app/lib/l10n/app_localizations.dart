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

  /// No description provided for @tripsEmptyUpcomingTitle.
  ///
  /// In en, this message translates to:
  /// **'No upcoming trips'**
  String get tripsEmptyUpcomingTitle;

  /// No description provided for @tripsEmptyPastTitle.
  ///
  /// In en, this message translates to:
  /// **'No past trips'**
  String get tripsEmptyPastTitle;

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

  /// No description provided for @tripsSectionUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get tripsSectionUpcoming;

  /// No description provided for @tripsSectionPast.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get tripsSectionPast;

  /// No description provided for @tripsParticipants.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Vamigo} other{{count} Vamigos}}'**
  String tripsParticipants(int count);

  /// No description provided for @tripsNotificationsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get tripsNotificationsTooltip;

  /// No description provided for @notificationsInboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsInboxTitle;

  /// No description provided for @notificationsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'All caught up'**
  String get notificationsEmptyTitle;

  /// No description provided for @notificationsEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Trip notices and reminders will show up here.'**
  String get notificationsEmptySubtitle;

  /// No description provided for @notificationsMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get notificationsMarkAllRead;

  /// No description provided for @notificationsUnreadBadge.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread} other{{count} unread}}'**
  String notificationsUnreadBadge(int count);

  /// No description provided for @notificationTypeCloseNotice.
  ///
  /// In en, this message translates to:
  /// **'Trip closing'**
  String get notificationTypeCloseNotice;

  /// No description provided for @notificationTypeCloseReminder.
  ///
  /// In en, this message translates to:
  /// **'Close reminder'**
  String get notificationTypeCloseReminder;

  /// No description provided for @notificationTypeDeemedClosed.
  ///
  /// In en, this message translates to:
  /// **'Trip closed'**
  String get notificationTypeDeemedClosed;

  /// No description provided for @notificationTypeSettleNudge.
  ///
  /// In en, this message translates to:
  /// **'Settle up'**
  String get notificationTypeSettleNudge;

  /// No description provided for @notificationTypeGeneric.
  ///
  /// In en, this message translates to:
  /// **'Notice'**
  String get notificationTypeGeneric;

  /// No description provided for @tripsCreateTripTooltip.
  ///
  /// In en, this message translates to:
  /// **'Create trip'**
  String get tripsCreateTripTooltip;

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

  /// No description provided for @inviteVamigos.
  ///
  /// In en, this message translates to:
  /// **'Invite Vamigos'**
  String get inviteVamigos;

  /// No description provided for @inviteShareJoinLink.
  ///
  /// In en, this message translates to:
  /// **'Share a join link'**
  String get inviteShareJoinLink;

  /// No description provided for @inviteFromContacts.
  ///
  /// In en, this message translates to:
  /// **'Invite from contacts'**
  String get inviteFromContacts;

  /// No description provided for @inviteContactMethodTextMessage.
  ///
  /// In en, this message translates to:
  /// **'Text message'**
  String get inviteContactMethodTextMessage;

  /// No description provided for @inviteContactMethodEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get inviteContactMethodEmail;

  /// No description provided for @inviteContactMethodShareLink.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get inviteContactMethodShareLink;

  /// No description provided for @inviteContactSubject.
  ///
  /// In en, this message translates to:
  /// **'Join my Vamo trip'**
  String get inviteContactSubject;

  /// No description provided for @inviteContactBody.
  ///
  /// In en, this message translates to:
  /// **'Join my trip on Vamo!\n{webUrl}\n\nHave the app? Tap: {appUri}'**
  String inviteContactBody(String webUrl, String appUri);

  /// No description provided for @membersVamigosTitle.
  ///
  /// In en, this message translates to:
  /// **'Vamigos'**
  String get membersVamigosTitle;

  /// No description provided for @membersInviteHintSolo.
  ///
  /// In en, this message translates to:
  /// **'Invite friends — balances unlock at 2+ people.'**
  String get membersInviteHintSolo;

  /// No description provided for @membersCountOnTrip.
  ///
  /// In en, this message translates to:
  /// **'{count} on this trip'**
  String membersCountOnTrip(int count);

  /// No description provided for @membersShareFootnote.
  ///
  /// In en, this message translates to:
  /// **'Share a link — they can join mid-trip. Opens Vamo or the store.'**
  String get membersShareFootnote;

  /// No description provided for @membersMakeCoAdmin.
  ///
  /// In en, this message translates to:
  /// **'Make co-admin'**
  String get membersMakeCoAdmin;

  /// No description provided for @membersRemoveCoAdmin.
  ///
  /// In en, this message translates to:
  /// **'Remove co-admin'**
  String get membersRemoveCoAdmin;

  /// No description provided for @inviteAction.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get inviteAction;

  /// No description provided for @tripHomeTabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get tripHomeTabOverview;

  /// No description provided for @tripHomeTabExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get tripHomeTabExpenses;

  /// No description provided for @tripHomeTabCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get tripHomeTabCapture;

  /// No description provided for @tripHomeMemories.
  ///
  /// In en, this message translates to:
  /// **'Memories'**
  String get tripHomeMemories;

  /// No description provided for @tripHomeTabBalances.
  ///
  /// In en, this message translates to:
  /// **'Balances'**
  String get tripHomeTabBalances;

  /// No description provided for @tripHomeTabMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get tripHomeTabMembers;

  /// No description provided for @tripHomeMoreMenu.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get tripHomeMoreMenu;

  /// No description provided for @tripHomeSettings.
  ///
  /// In en, this message translates to:
  /// **'Trip settings'**
  String get tripHomeSettings;

  /// No description provided for @tripHomeShareSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Share snapshot'**
  String get tripHomeShareSnapshot;

  /// No description provided for @tripHomeAddExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get tripHomeAddExpense;

  /// No description provided for @tripHomeLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load this trip.'**
  String get tripHomeLoadError;

  /// No description provided for @tripHomeNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip not found'**
  String get tripHomeNotFoundTitle;

  /// No description provided for @tripHomeNotFoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'It may have been removed or you no longer have access.'**
  String get tripHomeNotFoundSubtitle;

  /// No description provided for @tripHomeTotalSpent.
  ///
  /// In en, this message translates to:
  /// **'Total Spent'**
  String get tripHomeTotalSpent;

  /// No description provided for @tripHomePerPerson.
  ///
  /// In en, this message translates to:
  /// **'Per person {amount}'**
  String tripHomePerPerson(String amount);

  /// No description provided for @tripHomeRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get tripHomeRecentActivity;

  /// No description provided for @tripHomeNoRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'No expenses yet.'**
  String get tripHomeNoRecentActivity;

  /// No description provided for @tripHomeQuickExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get tripHomeQuickExpenses;

  /// No description provided for @tripHomeQuickPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get tripHomeQuickPlans;

  /// No description provided for @tripHomeQuickBalances.
  ///
  /// In en, this message translates to:
  /// **'Balances'**
  String get tripHomeQuickBalances;

  /// No description provided for @tripHomeQuickMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get tripHomeQuickMembers;

  /// No description provided for @tripHomeQuickMemories.
  ///
  /// In en, this message translates to:
  /// **'Memories'**
  String get tripHomeQuickMemories;

  /// No description provided for @tripHomeCloseReport.
  ///
  /// In en, this message translates to:
  /// **'Close report'**
  String get tripHomeCloseReport;

  /// No description provided for @closeReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Close report'**
  String get closeReportTitle;

  /// No description provided for @closeReportLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load the close report.'**
  String get closeReportLoadError;

  /// No description provided for @closeReportNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Close report is available when the trip is closing or closed.'**
  String get closeReportNotAvailable;

  /// No description provided for @closeReportBalancesTitle.
  ///
  /// In en, this message translates to:
  /// **'Final balances'**
  String get closeReportBalancesTitle;

  /// No description provided for @closeReportMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Close responses'**
  String get closeReportMembersTitle;

  /// No description provided for @closeReportDisputedTitle.
  ///
  /// In en, this message translates to:
  /// **'Disputed shares'**
  String get closeReportDisputedTitle;

  /// No description provided for @closeReportConsentAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted explicitly'**
  String get closeReportConsentAccepted;

  /// No description provided for @closeReportConsentObjected.
  ///
  /// In en, this message translates to:
  /// **'Objected'**
  String get closeReportConsentObjected;

  /// No description provided for @closeReportConsentDeemed.
  ///
  /// In en, this message translates to:
  /// **'Deemed (no response after notice)'**
  String get closeReportConsentDeemed;

  /// No description provided for @closeReportConsentPending.
  ///
  /// In en, this message translates to:
  /// **'Review in progress'**
  String get closeReportConsentPending;

  /// No description provided for @closeReportConsentNotNotified.
  ///
  /// In en, this message translates to:
  /// **'Not yet notified'**
  String get closeReportConsentNotNotified;

  /// No description provided for @closeReportBalanceLine.
  ///
  /// In en, this message translates to:
  /// **'{name} {direction} {amount}'**
  String closeReportBalanceLine(String name, String direction, String amount);

  /// No description provided for @closeReportNetOwed.
  ///
  /// In en, this message translates to:
  /// **'is owed'**
  String get closeReportNetOwed;

  /// No description provided for @closeReportNetOwes.
  ///
  /// In en, this message translates to:
  /// **'owes'**
  String get closeReportNetOwes;

  /// No description provided for @closeReportNoBalances.
  ///
  /// In en, this message translates to:
  /// **'All square — no open balances.'**
  String get closeReportNoBalances;

  /// No description provided for @balancesLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load balances.'**
  String get balancesLoadError;

  /// No description provided for @balancesWhoOwesTitle.
  ///
  /// In en, this message translates to:
  /// **'Who owes whom'**
  String get balancesWhoOwesTitle;

  /// No description provided for @balancesWhoOwesHint.
  ///
  /// In en, this message translates to:
  /// **'Fewest payments to clear the trip.'**
  String get balancesWhoOwesHint;

  /// No description provided for @balancesPaysLine.
  ///
  /// In en, this message translates to:
  /// **'{from} pays {to}'**
  String balancesPaysLine(String from, String to);

  /// No description provided for @balancesWaitingForPayer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {name} to pay'**
  String balancesWaitingForPayer(String name);

  /// No description provided for @balancesMarkSettled.
  ///
  /// In en, this message translates to:
  /// **'Mark as settled'**
  String get balancesMarkSettled;

  /// No description provided for @balancesMyActionTitle.
  ///
  /// In en, this message translates to:
  /// **'Your action'**
  String get balancesMyActionTitle;

  /// No description provided for @balancesConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Marked as paid — confirm if you received it, or reject if not.'**
  String get balancesConfirmHint;

  /// No description provided for @balancesConfirmFrom.
  ///
  /// In en, this message translates to:
  /// **'{name} says they paid you'**
  String balancesConfirmFrom(String name);

  /// No description provided for @balancesConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get balancesConfirm;

  /// No description provided for @balancesReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get balancesReject;

  /// No description provided for @balancesAwaitingTitle.
  ///
  /// In en, this message translates to:
  /// **'Awaiting confirmation'**
  String get balancesAwaitingTitle;

  /// No description provided for @balancesAwaitingHint.
  ///
  /// In en, this message translates to:
  /// **'You marked these paid — recipients can confirm or reject. Cancel if you did not actually pay.'**
  String get balancesAwaitingHint;

  /// No description provided for @balancesYouToRecipient.
  ///
  /// In en, this message translates to:
  /// **'You → {name}'**
  String balancesYouToRecipient(String name);

  /// No description provided for @balancesMarkedNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'{amount} · marked, not confirmed'**
  String balancesMarkedNotConfirmed(String amount);

  /// No description provided for @balancesCancelMark.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get balancesCancelMark;

  /// No description provided for @balancesDisputedTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s disputed'**
  String get balancesDisputedTitle;

  /// No description provided for @balancesFinalTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s final'**
  String get balancesFinalTitle;

  /// No description provided for @balancesNetLine.
  ///
  /// In en, this message translates to:
  /// **'{name} {direction} {amount}'**
  String balancesNetLine(String name, String direction, String amount);

  /// No description provided for @balancesNetOwed.
  ///
  /// In en, this message translates to:
  /// **'is owed'**
  String get balancesNetOwed;

  /// No description provided for @balancesNetOwes.
  ///
  /// In en, this message translates to:
  /// **'owes'**
  String get balancesNetOwes;

  /// No description provided for @balancesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'All square'**
  String get balancesEmptyTitle;

  /// No description provided for @balancesEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'No open debts — add expenses or invite Vamigos.'**
  String get balancesEmptySubtitle;

  /// No description provided for @balancesPaymentConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Payment confirmed.'**
  String get balancesPaymentConfirmed;

  /// No description provided for @balancesMarkedNotReceived.
  ///
  /// In en, this message translates to:
  /// **'Marked as not received.'**
  String get balancesMarkedNotReceived;

  /// No description provided for @balancesMarkCancelled.
  ///
  /// In en, this message translates to:
  /// **'Mark cancelled — debt is back on your balance.'**
  String get balancesMarkCancelled;

  /// No description provided for @authContinueEmail.
  ///
  /// In en, this message translates to:
  /// **'Continue with email'**
  String get authContinueEmail;

  /// No description provided for @authEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// No description provided for @authEmailHint.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get authEmailHint;

  /// No description provided for @authOtpLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get authOtpLabel;

  /// No description provided for @authCodeSent.
  ///
  /// In en, this message translates to:
  /// **'We sent a code to {email}'**
  String authCodeSent(String email);

  /// No description provided for @authVerifyContinue.
  ///
  /// In en, this message translates to:
  /// **'Verify & continue'**
  String get authVerifyContinue;

  /// No description provided for @authDifferentEmail.
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get authDifferentEmail;

  /// No description provided for @authOrDivider.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOrDivider;

  /// No description provided for @authContinueApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get authContinueApple;

  /// No description provided for @authContinueGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueGoogle;

  /// No description provided for @authResendCode.
  ///
  /// In en, this message translates to:
  /// **'Send me a new code'**
  String get authResendCode;

  /// No description provided for @authResendCodeCooldown.
  ///
  /// In en, this message translates to:
  /// **'Send me a new code ({seconds}s)'**
  String authResendCodeCooldown(int seconds);

  /// No description provided for @createTripTitle.
  ///
  /// In en, this message translates to:
  /// **'New trip'**
  String get createTripTitle;

  /// No description provided for @createTripHeadline.
  ///
  /// In en, this message translates to:
  /// **'Si va?'**
  String get createTripHeadline;

  /// No description provided for @createTripSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start solo — you can invite Vamigos later.'**
  String get createTripSubtitle;

  /// No description provided for @createTripNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Trip name'**
  String get createTripNameLabel;

  /// No description provided for @createTripNameHint.
  ///
  /// In en, this message translates to:
  /// **'Amalfi with the crew'**
  String get createTripNameHint;

  /// No description provided for @createTripNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Give your trip a name'**
  String get createTripNameRequired;

  /// No description provided for @createTripDestinationLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination (optional)'**
  String get createTripDestinationLabel;

  /// No description provided for @createTripDestinationHint.
  ///
  /// In en, this message translates to:
  /// **'Positano, Italy'**
  String get createTripDestinationHint;

  /// No description provided for @createTripCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Base currency'**
  String get createTripCurrencyLabel;

  /// No description provided for @createTripStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get createTripStartDate;

  /// No description provided for @createTripEndDate.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get createTripEndDate;

  /// No description provided for @createTripSubmit.
  ///
  /// In en, this message translates to:
  /// **'Create trip'**
  String get createTripSubmit;

  /// No description provided for @createTripEndBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'End date must be on or after start date.'**
  String get createTripEndBeforeStart;

  /// No description provided for @createTripClearDate.
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get createTripClearDate;

  /// No description provided for @datePickerCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get datePickerCancel;

  /// No description provided for @datePickerSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get datePickerSkip;

  /// No description provided for @datePickerSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get datePickerSelect;

  /// No description provided for @addExpenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get addExpenseTitle;

  /// No description provided for @addExpenseTripNotFound.
  ///
  /// In en, this message translates to:
  /// **'Trip not found'**
  String get addExpenseTripNotFound;

  /// No description provided for @addExpenseScanReceipt.
  ///
  /// In en, this message translates to:
  /// **'Scan receipt'**
  String get addExpenseScanReceipt;

  /// No description provided for @addExpenseTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get addExpenseTakePhoto;

  /// No description provided for @addExpenseChooseGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get addExpenseChooseGallery;

  /// No description provided for @addExpenseChoosePayer.
  ///
  /// In en, this message translates to:
  /// **'Choose who paid.'**
  String get addExpenseChoosePayer;

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

  /// No description provided for @profileAppearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get profileAppearanceSection;

  /// No description provided for @profileAppearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get profileAppearanceLight;

  /// No description provided for @profileAppearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get profileAppearanceDark;

  /// No description provided for @profileAppearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get profileAppearanceSystem;

  /// No description provided for @profilePrivacySection.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get profilePrivacySection;

  /// No description provided for @profileTagCaptureLocation.
  ///
  /// In en, this message translates to:
  /// **'Tag captures with location'**
  String get profileTagCaptureLocation;

  /// No description provided for @profileTagCaptureLocationHelper.
  ///
  /// In en, this message translates to:
  /// **'When on, new trip photos can save location and original photo time from the image file. Existing photos are not scanned.'**
  String get profileTagCaptureLocationHelper;

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

  /// No description provided for @planAddChecklistItem.
  ///
  /// In en, this message translates to:
  /// **'Add checklist item'**
  String get planAddChecklistItem;

  /// No description provided for @planDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this item?'**
  String get planDeleteConfirmTitle;

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

  /// No description provided for @planFieldKind.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get planFieldKind;

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

  /// No description provided for @planEndBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'End must be on or after start.'**
  String get planEndBeforeStart;

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

  /// No description provided for @eventRsvpGoing.
  ///
  /// In en, this message translates to:
  /// **'Going'**
  String get eventRsvpGoing;

  /// No description provided for @eventRsvpMaybe.
  ///
  /// In en, this message translates to:
  /// **'Maybe'**
  String get eventRsvpMaybe;

  /// No description provided for @eventRsvpDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get eventRsvpDeclined;

  /// No description provided for @eventRsvpSummary.
  ///
  /// In en, this message translates to:
  /// **'{going} going · {maybe} maybe · {declined} declined'**
  String eventRsvpSummary(int going, int maybe, int declined);

  /// No description provided for @planEventRsvpHint.
  ///
  /// In en, this message translates to:
  /// **'After you save, you and other Vamigos can RSVP on the plan board.'**
  String get planEventRsvpHint;

  /// No description provided for @planEventRsvpSection.
  ///
  /// In en, this message translates to:
  /// **'RSVP'**
  String get planEventRsvpSection;

  /// No description provided for @eventRsvpUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update RSVP. Try again.'**
  String get eventRsvpUpdateFailed;

  /// No description provided for @activityEventCreatedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Event added'**
  String get activityEventCreatedSubtitle;

  /// No description provided for @activityEventRsvpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'RSVP: {status}'**
  String activityEventRsvpSubtitle(String status);

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

  /// No description provided for @tripLifecycleMarkDone.
  ///
  /// In en, this message translates to:
  /// **'I\'m done'**
  String get tripLifecycleMarkDone;

  /// No description provided for @tripLifecycleRequestClose.
  ///
  /// In en, this message translates to:
  /// **'Request close'**
  String get tripLifecycleRequestClose;

  /// No description provided for @tripLifecycleCancelTrip.
  ///
  /// In en, this message translates to:
  /// **'Cancel trip'**
  String get tripLifecycleCancelTrip;

  /// No description provided for @tripLifecycleAcceptClose.
  ///
  /// In en, this message translates to:
  /// **'Accept close'**
  String get tripLifecycleAcceptClose;

  /// No description provided for @tripLifecycleObject.
  ///
  /// In en, this message translates to:
  /// **'Object…'**
  String get tripLifecycleObject;

  /// No description provided for @tripLifecycleWithdrawObjection.
  ///
  /// In en, this message translates to:
  /// **'Withdraw objection'**
  String get tripLifecycleWithdrawObjection;

  /// No description provided for @tripLifecycleCloseAnyway.
  ///
  /// In en, this message translates to:
  /// **'Close anyway'**
  String get tripLifecycleCloseAnyway;

  /// No description provided for @tripLifecycleCancelledBanner.
  ///
  /// In en, this message translates to:
  /// **'Trip cancelled — no further activity.'**
  String get tripLifecycleCancelledBanner;

  /// No description provided for @tripLifecycleClosedBanner.
  ///
  /// In en, this message translates to:
  /// **'Trip closed — settling still open.'**
  String get tripLifecycleClosedBanner;

  /// No description provided for @tripLifecycleClosingGeneric.
  ///
  /// In en, this message translates to:
  /// **'Trip is closing — review balances and respond.'**
  String get tripLifecycleClosingGeneric;

  /// No description provided for @tripLifecycleClosingCountdown.
  ///
  /// In en, this message translates to:
  /// **'Trip closes in {days} days unless someone objects.'**
  String tripLifecycleClosingCountdown(int days);

  /// No description provided for @tripLifecycleObjectionNotice.
  ///
  /// In en, this message translates to:
  /// **'A member objected to closing — discuss or owner may close anyway.'**
  String get tripLifecycleObjectionNotice;

  /// No description provided for @tripLifecycleMarkDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark yourself done?'**
  String get tripLifecycleMarkDoneTitle;

  /// No description provided for @tripLifecycleMarkDoneBody.
  ///
  /// In en, this message translates to:
  /// **'You can still log expenses until the trip closes. When everyone is done, the close review starts.'**
  String get tripLifecycleMarkDoneBody;

  /// No description provided for @tripLifecycleMarkDoneConfirm.
  ///
  /// In en, this message translates to:
  /// **'I\'m done'**
  String get tripLifecycleMarkDoneConfirm;

  /// No description provided for @tripLifecycleNotYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get tripLifecycleNotYet;

  /// No description provided for @tripLifecycleCancelTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this trip?'**
  String get tripLifecycleCancelTitle;

  /// No description provided for @tripLifecycleCancelBody.
  ///
  /// In en, this message translates to:
  /// **'Only possible before the start date. Members will be notified.'**
  String get tripLifecycleCancelBody;

  /// No description provided for @tripLifecycleKeepTrip.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get tripLifecycleKeepTrip;

  /// No description provided for @tripLifecycleRequestCloseTitle.
  ///
  /// In en, this message translates to:
  /// **'Request trip close?'**
  String get tripLifecycleRequestCloseTitle;

  /// No description provided for @tripLifecycleRequestCloseBody.
  ///
  /// In en, this message translates to:
  /// **'Members get 14 days to review balances and accept or object. You can still log expenses during the review.'**
  String get tripLifecycleRequestCloseBody;

  /// No description provided for @tripLifecycleRequestCloseConfirm.
  ///
  /// In en, this message translates to:
  /// **'Request close'**
  String get tripLifecycleRequestCloseConfirm;

  /// No description provided for @tripLifecycleTripActions.
  ///
  /// In en, this message translates to:
  /// **'Trip actions'**
  String get tripLifecycleTripActions;

  /// No description provided for @tripLifecycleCloseAnywayTitle.
  ///
  /// In en, this message translates to:
  /// **'Close anyway?'**
  String get tripLifecycleCloseAnywayTitle;

  /// No description provided for @tripLifecycleCloseAnywayBody.
  ///
  /// In en, this message translates to:
  /// **'An objection is on record. Force-close keeps it visible in the close report.'**
  String get tripLifecycleCloseAnywayBody;

  /// No description provided for @tripLifecycleCloseAnywayHint.
  ///
  /// In en, this message translates to:
  /// **'Type CLOSE to confirm'**
  String get tripLifecycleCloseAnywayHint;

  /// No description provided for @tripLifecycleCloseAnywayPhrase.
  ///
  /// In en, this message translates to:
  /// **'CLOSE'**
  String get tripLifecycleCloseAnywayPhrase;

  /// No description provided for @tripLifecycleCloseTrip.
  ///
  /// In en, this message translates to:
  /// **'Close trip'**
  String get tripLifecycleCloseTrip;

  /// No description provided for @tripLifecycleBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get tripLifecycleBack;

  /// No description provided for @tripLifecycleObjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Object to closing'**
  String get tripLifecycleObjectTitle;

  /// No description provided for @tripLifecycleObjectReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason (required)'**
  String get tripLifecycleObjectReasonLabel;

  /// No description provided for @tripLifecycleObjectReasonHint.
  ///
  /// In en, this message translates to:
  /// **'What still needs resolving?'**
  String get tripLifecycleObjectReasonHint;

  /// No description provided for @tripLifecycleSubmitObjection.
  ///
  /// In en, this message translates to:
  /// **'Submit objection'**
  String get tripLifecycleSubmitObjection;
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
