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
    required this.kindOther,
    required this.sheetTitleAdd,
    required this.sheetTitleEdit,
    required this.fieldTitle,
    required this.fieldKind,
    required this.fieldNotes,
    required this.fieldStart,
    required this.fieldEnd,
    required this.save,
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
  final String kindOther;
  final String sheetTitleAdd;
  final String sheetTitleEdit;
  final String fieldTitle;
  final String fieldKind;
  final String fieldNotes;
  final String fieldStart;
  final String fieldEnd;
  final String save;
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
        PlanItemKind.other => kindOther,
      };
}
