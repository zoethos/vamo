import 'package:feature_split/feature_split.dart';

import 'l10n/app_localizations.dart';

/// Maps generated ARB strings to feature_split label bundles.
class SplitLabels {
  SplitLabels._();

  static MainShellLabels shell(AppLocalizations l10n) => MainShellLabels(
        trips: l10n.navTrips,
        activity: l10n.navActivity,
        expenses: l10n.navExpenses,
        profile: l10n.navProfile,
      );

  static TripsListScreenLabels trips(AppLocalizations l10n) =>
      TripsListScreenLabels(
        title: l10n.tripsTitle,
        emptyTitle: l10n.tripsEmptyTitle,
        emptySubtitle: l10n.tripsEmptySubtitle,
        syncPendingLabel: l10n.tripsSyncPending,
        syncSubtitle: l10n.tripsSyncSubtitle,
        filterAll: l10n.tripsFilterAll,
        filterUpcoming: l10n.tripsFilterUpcoming,
        filterPast: l10n.tripsFilterPast,
        filterDrafts: l10n.tripsFilterDrafts,
        loadError: l10n.tripsLoadError,
        syncError: l10n.tripsSyncError,
      );

  static ActivityScreenLabels activity(AppLocalizations l10n) =>
      ActivityScreenLabels(
        title: l10n.activityTitle,
        emptyTitle: l10n.activityEmptyTitle,
        emptySubtitle: l10n.activityEmptySubtitle,
        loadError: l10n.activityLoadError,
      );

  static ExpensesListScreenLabels expenses(AppLocalizations l10n) =>
      ExpensesListScreenLabels(
        title: l10n.expensesTitle,
        emptyTitle: l10n.expensesEmptyTitle,
        emptySubtitle: l10n.expensesEmptySubtitle,
        loadError: l10n.expensesLoadError,
        allTrips: l10n.expensesAllTrips,
      );

  static ProfileScreenLabels profile(AppLocalizations l10n) =>
      ProfileScreenLabels(
        title: l10n.profileTitle,
        aboutSection: l10n.profileAbout,
        versionLabel: l10n.profileVersion,
        licenses: l10n.profileLicenses,
        privacyPolicy: l10n.profilePrivacy,
        tagline: l10n.brandTagline,
        loadError: l10n.profileLoadError,
        profileSection: l10n.profileSection,
        displayName: l10n.profileDisplayName,
        displayNameHint: l10n.profileDisplayNameHint,
        defaultCurrency: l10n.profileDefaultCurrency,
        defaultCurrencyHelper: l10n.profileDefaultCurrencyHelper,
        billingSection: l10n.profileBilling,
        plusTitle: l10n.profilePlusTitle,
        plusSubtitle: l10n.profilePlusSubtitle,
        plusSheetDescription: l10n.profilePlusSheetDescription,
        suggestTitle: l10n.profileSuggestTitle,
        suggestSubtitle: l10n.profileSuggestSubtitle,
        devLocaleSection: l10n.settingsDevLocaleSection,
        devLocaleSystem: l10n.settingsDevLocaleSystem,
        devLocaleRtl: l10n.settingsDevLocaleRtl,
        devLocalePseudo: l10n.settingsDevLocalePseudo,
        analyticsSection: l10n.profileAnalytics,
        analyticsHint: l10n.profileAnalyticsHint,
        posthogActive: l10n.profilePosthogActive,
        signOut: l10n.profileSignOut,
        saveChanges: l10n.profileSave,
        profileSaved: l10n.profileSaved,
      );
}
