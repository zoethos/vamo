import 'package:feature_split/src/expenses/add_expense_screen_labels.dart';

const addExpenseTestScreenLabels = AddExpenseScreenLabels(
  title: 'Add expense',
  tripNotFound: 'Trip not found',
  scanReceipt: 'Scan receipt',
  takePhoto: 'Take photo',
  chooseGallery: 'Choose from gallery',
  choosePayer: 'Choose who paid.',
  youPaid: 'You paid',
  paidBy: _mockPaidBy,
  splitSection: 'Split',
  splitEqual: 'Equal',
  splitCustom: 'Custom',
  customSplitComingSoon: 'Custom split — coming soon',
  splitEach: _mockSplitEach,
  attachReceipt: 'Receipt',
  addPlace: 'Place',
  addNote: 'Add note',
  descriptionHint: 'Dinner',
  currencySheetTitle: 'Currency',
  categorySheetTitle: 'Category',
  payerSheetTitle: 'Who paid?',
  done: 'Done',
  descriptionRequired: 'Add a short description',
  readingReceipt: 'Reading receipt…',
  receiptAttached: 'Receipt attached',
  removeReceipt: 'Remove receipt',
);

String _mockPaidBy(String name) => '$name paid';
String _mockSplitEach(String amount) => 'Equally · $amount each';
