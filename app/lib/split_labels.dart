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
        eventCreatedSubtitle: l10n.activityEventCreatedSubtitle,
        eventRsvpSubtitle: (status) => l10n.activityEventRsvpSubtitle(status),
        rsvpGoing: l10n.eventRsvpGoing,
        rsvpMaybe: l10n.eventRsvpMaybe,
        rsvpDeclined: l10n.eventRsvpDeclined,
      );

  static ExpensesListScreenLabels expenses(AppLocalizations l10n) =>
      ExpensesListScreenLabels(
        title: l10n.expensesTitle,
        emptyTitle: l10n.expensesEmptyTitle,
        emptySubtitle: l10n.expensesEmptySubtitle,
        loadError: l10n.expensesLoadError,
        balanceAllSettled: l10n.expensesBalanceAllSettled,
        balanceYouOwe: l10n.expensesBalanceYouOwe,
        balanceYouAreOwed: l10n.expensesBalanceYouAreOwed,
        balanceAcrossTrips: l10n.expensesBalanceAcrossTrips,
        periodThisMonth: l10n.expensesPeriodThisMonth,
        periodThisYear: l10n.expensesPeriodThisYear,
        earlierSection: l10n.expensesEarlierSection,
        totalSpent: l10n.expensesTotalSpent,
        myShare: l10n.expensesMyShare,
        settlementUnsettled: l10n.expensesSettlementUnsettled,
        settlementSettled: l10n.expensesSettlementSettled,
        settlementAllSettled: l10n.expensesSettlementAllSettled,
        unresolvedBadge: l10n.expensesUnresolvedBadge,
        pickerTitle: l10n.expensesPickerTitle,
        pickerLastUsed: l10n.expensesPickerLastUsed,
      );

  static ExpensesFabLabels expensesFab(AppLocalizations l10n) =>
      ExpensesFabLabels(
        pickerTitle: l10n.expensesPickerTitle,
        pickerLastUsed: l10n.expensesPickerLastUsed,
      );

  static PlanTabLabels plan(AppLocalizations l10n) => PlanTabLabels(
        tabTitle: l10n.planTabTitle,
        emptyTitle: l10n.planEmptyTitle,
        emptySubtitle: l10n.planEmptySubtitle,
        undatedSection: l10n.planUndatedSection,
        checklistsSection: l10n.planChecklistsSection,
        addPlanItem: l10n.planAddItem,
        addListItemHint: l10n.planAddListItemHint,
        defaultListName: l10n.planDefaultListName,
        deleteItem: l10n.planDeleteItem,
        editItem: l10n.planEditItem,
        kindLodging: l10n.planKindLodging,
        kindFlight: l10n.planKindFlight,
        kindTrain: l10n.planKindTrain,
        kindActivity: l10n.planKindActivity,
        kindOther: l10n.planKindOther,
        sheetTitleAdd: l10n.planSheetTitleAdd,
        sheetTitleEdit: l10n.planSheetTitleEdit,
        fieldTitle: l10n.planFieldTitle,
        fieldKind: l10n.planFieldKind,
        fieldNotes: l10n.planFieldNotes,
        fieldStart: l10n.planFieldStart,
        fieldEnd: l10n.planFieldEnd,
        save: l10n.planSave,
        loadError: l10n.planLoadError,
        checklistsLoadError: l10n.planChecklistsLoadError,
        rsvpGoing: l10n.eventRsvpGoing,
        rsvpMaybe: l10n.eventRsvpMaybe,
        rsvpDeclined: l10n.eventRsvpDeclined,
        rsvpSummary: (going, maybe) => l10n.eventRsvpSummary(going, maybe),
        eventRsvpHint: l10n.planEventRsvpHint,
        eventRsvpSection: l10n.planEventRsvpSection,
      );

  static ExpenseGovernanceLabels governance(AppLocalizations l10n) =>
      ExpenseGovernanceLabels(
        includedDisputedBy: l10n.expenseIncludedDisputedBy,
        includedPendingFrom: l10n.expenseIncludedPendingFrom,
        someoneFallback: l10n.expenseSomeoneFallback,
        proposalRowPrefix: l10n.expenseProposalRowPrefix,
        proposalNotInBalances: l10n.expenseProposalNotInBalances,
        shareAccepted: l10n.expenseShareAccepted,
        yourShare: l10n.expenseYourShare,
        dispute: l10n.expenseDispute,
        accept: l10n.expenseAccept,
        commitToBalances: l10n.expenseCommitToBalances,
        voidProposal: l10n.expenseVoidProposal,
        disputeReasonTitle: l10n.expenseDisputeReasonTitle,
        disputeReasonHint: l10n.expenseDisputeReasonHint,
        cancel: l10n.expenseGovernanceCancel,
        submit: l10n.expenseGovernanceSubmit,
        proposeCostAction: l10n.expenseProposeCostAction,
        addExpenseTitle: l10n.expenseAddTitle,
        proposeCostTitle: l10n.expenseProposeCostTitle,
        saveExpense: l10n.expenseSaveExpense,
        saveProposal: l10n.expenseSaveProposal,
        tripBalancesIn: l10n.expenseTripBalancesIn,
        splitEqual: l10n.expenseSplitEqual,
        splitSolo: l10n.expenseSplitSolo,
      );

  static TripBudgetLabels budget(AppLocalizations l10n) => TripBudgetLabels(
        settingsTitle: l10n.tripSettingsTitle,
        budgetSectionTitle: l10n.tripBudgetSectionTitle,
        budgetModeNone: l10n.tripBudgetModeNone,
        budgetModeInformational: l10n.tripBudgetModeInformational,
        budgetModeFormal: l10n.tripBudgetModeFormal,
        budgetAmountLabel: l10n.tripBudgetAmountLabel,
        saveBudget: l10n.tripBudgetSave,
        burnDownRemaining: (remainingCents, currency) =>
            l10n.tripBudgetRemaining(
          formatMoneyFromCents(remainingCents, currency),
          currency,
        ),
        burnDownOver: (currency) => l10n.tripBudgetOver(currency),
        fxSectionTitle: l10n.tripFxSectionTitle,
        fxAddCurrency: l10n.tripFxAddCurrency,
        fxRefresh: l10n.tripFxRefresh,
        fxCapturedAt: l10n.tripFxCapturedAt,
        fxSource: l10n.tripFxSource,
        fxRateReadOnly: l10n.tripFxRateReadOnly,
        overBudgetCommitTitle: l10n.tripOverBudgetCommitTitle,
        overBudgetCommitBody: l10n.tripOverBudgetCommitBody,
        overBudgetConfirmHint: l10n.tripOverBudgetConfirmHint,
        overBudgetConfirmPhrase: l10n.tripOverBudgetConfirmPhrase,
        confirm: l10n.tripBudgetConfirm,
        cancel: l10n.tripBudgetCancel,
        currencyMissingAdmin: l10n.tripCurrencyMissingAdmin,
      );

  static TripLifecycleLabels lifecycle(AppLocalizations l10n) =>
      TripLifecycleLabels(
        markDone: l10n.tripLifecycleMarkDone,
        requestClose: l10n.tripLifecycleRequestClose,
        cancelTrip: l10n.tripLifecycleCancelTrip,
        acceptClose: l10n.tripLifecycleAcceptClose,
        objectToClose: l10n.tripLifecycleObject,
        withdrawObjection: l10n.tripLifecycleWithdrawObjection,
        closeAnyway: l10n.tripLifecycleCloseAnyway,
        cancelledBanner: l10n.tripLifecycleCancelledBanner,
        closedBanner: l10n.tripLifecycleClosedBanner,
        closingBannerGeneric: l10n.tripLifecycleClosingGeneric,
        closingBannerDays: l10n.tripLifecycleClosingCountdown,
        objectionNotice: l10n.tripLifecycleObjectionNotice,
        markDoneTitle: l10n.tripLifecycleMarkDoneTitle,
        markDoneBody: l10n.tripLifecycleMarkDoneBody,
        markDoneConfirm: l10n.tripLifecycleMarkDoneConfirm,
        notYet: l10n.tripLifecycleNotYet,
        cancelTripTitle: l10n.tripLifecycleCancelTitle,
        cancelTripBody: l10n.tripLifecycleCancelBody,
        keepTrip: l10n.tripLifecycleKeepTrip,
        requestCloseTitle: l10n.tripLifecycleRequestCloseTitle,
        requestCloseBody: l10n.tripLifecycleRequestCloseBody,
        requestCloseConfirm: l10n.tripLifecycleRequestCloseConfirm,
        tripActions: l10n.tripLifecycleTripActions,
        closeAnywayTitle: l10n.tripLifecycleCloseAnywayTitle,
        closeAnywayBody: l10n.tripLifecycleCloseAnywayBody,
        closeAnywayHint: l10n.tripLifecycleCloseAnywayHint,
        closeAnywayPhrase: l10n.tripLifecycleCloseAnywayPhrase,
        closeTrip: l10n.tripLifecycleCloseTrip,
        back: l10n.tripLifecycleBack,
        objectTitle: l10n.tripLifecycleObjectTitle,
        objectReasonLabel: l10n.tripLifecycleObjectReasonLabel,
        objectReasonHint: l10n.tripLifecycleObjectReasonHint,
        submitObjection: l10n.tripLifecycleSubmitObjection,
      );

  static InviteLabels invite(AppLocalizations l10n) => InviteLabels(
        showQr: l10n.inviteShowQr,
        scanQr: l10n.inviteScanQr,
        qrCaption: l10n.inviteQrCaption,
        notVamoInvite: l10n.inviteNotVamoQr,
        cameraDenied: l10n.inviteCameraDenied,
        pasteLink: l10n.invitePasteLink,
        pasteHint: l10n.invitePasteHint,
        pasteJoin: l10n.invitePasteJoin,
        scannerTitle: l10n.inviteScannerTitle,
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
