import 'plan_models.dart';

class PlanTabLabels {
  PlanTabLabels({
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.undatedSection,
    required this.checklistsSection,
    required this.addPlanItem,
    required this.addListItemHint,
    required this.defaultListName,
    required this.deleteItem,
    required this.editItem,
    required this.kindLodging,
    required this.kindFlight,
    required this.kindTrain,
    required this.kindActivity,
    required this.kindVisit,
    required this.kindTransfer,
    required this.kindOther,
    required this.sheetTitleAdd,
    required this.sheetTitleEdit,
    required this.fieldTitle,
    required this.fieldKind,
    required this.fieldNotes,
    required this.fieldStart,
    required this.fieldEnd,
    required this.visitSectionTitle,
    required this.visitFromTripPlaces,
    required this.visitPlaceLabel,
    this.visitPlaceHelper = 'Start typing a place…',
    required this.visitAddressLabel,
    this.visitAddressHelper = 'Optional',
    this.visitAddNote = 'Add a note',
    required this.visitFindCoordinates,
    required this.visitPlaceRequired,
    required this.visitAddressRequiredForGeocode,
    required this.visitCoordinatesSaved,
    required this.visitCoordinatesNotFound,
    this.visitDiscoverNearby = 'Search places',
    this.visitDiscoverHelper =
        'Suggestions follow what you type. You can always save manually.',
    this.visitDiscoverNeedsPlace = 'Type a place or address first.',
    this.visitDiscoverResolving = 'Finding matching places...',
    this.visitDiscoverNeedsCoordinates = 'Type a place or address first.',
    this.visitDiscoverEmpty = 'No matches — you can still save manually.',
    this.visitDiscoverGated =
        'You have used your free place lookups this month. Vamo Plus unlocks more.',
    this.visitDiscoverLoadError =
        'Could not load suggestions. You can still save manually.',
    required this.transferSectionTitle,
    required this.transferSubtypeLabel,
    required this.transferOriginLabel,
    required this.transferDestinationLabel,
    required this.transferProviderLabel,
    required this.transferReferenceLabel,
    required this.transferSubtypeCarRental,
    required this.transferSubtypeTrain,
    required this.transferSubtypeTransit,
    required this.transferSubtypeDrive,
    required this.transferSubtypeFlight,
    required this.save,
    this.visitSave = 'Add Visit',
    this.ctaTapType = 'tap a type',
    this.ctaTapPlace = 'tap a place',
    required this.tabTitle,
    required this.loadError,
    required this.checklistsLoadError,
    required this.rsvpGoing,
    required this.rsvpMaybe,
    required this.rsvpDeclined,
    required this.rsvpSummary,
    required this.eventRsvpHint,
    required this.eventRsvpSection,
    required this.eventRsvpUpdateFailed,
    required this.datePickerCancel,
    required this.datePickerSkip,
    required this.datePickerSelect,
    required this.addChecklistItem,
    required this.deleteConfirmTitle,
    required this.endBeforeStart,
    required this.cancelLabel,
  });

  final String emptyTitle;
  final String emptySubtitle;
  final String undatedSection;
  final String checklistsSection;
  final String addPlanItem;
  final String addListItemHint;
  final String defaultListName;
  final String deleteItem;
  final String editItem;
  final String kindLodging;
  final String kindFlight;
  final String kindTrain;
  final String kindActivity;
  final String kindVisit;
  final String kindTransfer;
  final String kindOther;
  final String sheetTitleAdd;
  final String sheetTitleEdit;
  final String fieldTitle;
  final String fieldKind;
  final String fieldNotes;
  final String fieldStart;
  final String fieldEnd;
  final String visitSectionTitle;
  final String visitFromTripPlaces;
  final String visitPlaceLabel;
  final String visitPlaceHelper;
  final String visitAddressLabel;
  final String visitAddressHelper;
  final String visitAddNote;
  final String visitFindCoordinates;
  final String visitPlaceRequired;
  final String visitAddressRequiredForGeocode;
  final String visitCoordinatesSaved;
  final String visitCoordinatesNotFound;
  final String visitDiscoverNearby;
  final String visitDiscoverHelper;
  final String visitDiscoverNeedsPlace;
  final String visitDiscoverResolving;
  final String visitDiscoverNeedsCoordinates;
  final String visitDiscoverEmpty;
  final String visitDiscoverGated;
  final String visitDiscoverLoadError;
  final String transferSectionTitle;
  final String transferSubtypeLabel;
  final String transferOriginLabel;
  final String transferDestinationLabel;
  final String transferProviderLabel;
  final String transferReferenceLabel;
  final String transferSubtypeCarRental;
  final String transferSubtypeTrain;
  final String transferSubtypeTransit;
  final String transferSubtypeDrive;
  final String transferSubtypeFlight;
  final String save;
  final String visitSave;
  final String ctaTapType;
  final String ctaTapPlace;
  final String tabTitle;
  final String loadError;
  final String checklistsLoadError;
  final String rsvpGoing;
  final String rsvpMaybe;
  final String rsvpDeclined;
  final String Function(int going, int maybe, int declined) rsvpSummary;
  final String eventRsvpHint;
  final String eventRsvpSection;
  final String eventRsvpUpdateFailed;
  final String datePickerCancel;
  final String datePickerSkip;
  final String datePickerSelect;
  final String addChecklistItem;
  final String deleteConfirmTitle;
  final String endBeforeStart;
  final String cancelLabel;

  String kindLabel(PlanItemKind kind) => switch (kind) {
    PlanItemKind.lodging => kindLodging,
    PlanItemKind.flight => kindFlight,
    PlanItemKind.train => kindTrain,
    PlanItemKind.activity => kindActivity,
    PlanItemKind.visit => kindVisit,
    PlanItemKind.transfer => kindTransfer,
    PlanItemKind.other => kindOther,
  };

  String transferSubtype(TransferSubtype subtype) => switch (subtype) {
    TransferSubtype.carRental => transferSubtypeCarRental,
    TransferSubtype.train => transferSubtypeTrain,
    TransferSubtype.transit => transferSubtypeTransit,
    TransferSubtype.drive => transferSubtypeDrive,
    TransferSubtype.flight => transferSubtypeFlight,
  };
}
