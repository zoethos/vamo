/// Localized copy for add-expense screen (S27 + amount-first redesign).
class AddExpenseScreenLabels {
  const AddExpenseScreenLabels({
    required this.title,
    required this.tripNotFound,
    required this.scanReceipt,
    required this.takePhoto,
    required this.chooseGallery,
    required this.choosePayer,
    required this.youPaid,
    required this.paidBy,
    required this.splitSection,
    required this.splitEqual,
    required this.splitCustom,
    required this.customSplitComingSoon,
    required this.splitEach,
    required this.attachReceipt,
    required this.addPlace,
    required this.addNote,
    required this.descriptionHint,
    required this.currencySheetTitle,
    required this.categorySheetTitle,
    required this.payerSheetTitle,
    required this.done,
    required this.descriptionRequired,
    required this.readingReceipt,
    required this.receiptAttached,
    required this.removeReceipt,
  });

  final String title;
  final String tripNotFound;
  final String scanReceipt;
  final String takePhoto;
  final String chooseGallery;
  final String choosePayer;
  final String youPaid;
  final String Function(String name) paidBy;
  final String splitSection;
  final String splitEqual;
  final String splitCustom;
  final String customSplitComingSoon;
  final String Function(String amount) splitEach;
  final String attachReceipt;
  final String addPlace;
  final String addNote;
  final String descriptionHint;
  final String currencySheetTitle;
  final String categorySheetTitle;
  final String payerSheetTitle;
  final String done;
  final String descriptionRequired;
  final String readingReceipt;
  final String receiptAttached;
  final String removeReceipt;
}
