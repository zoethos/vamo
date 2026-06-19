import 'package:feature_split/src/expenses/expense_governance_labels.dart';

const governanceTestLabels = ExpenseGovernanceLabels(
  includedDisputedBy: _mockDisputedBy,
  includedPendingFrom: _mockPendingFrom,
  someoneFallback: 'Someone',
  proposalRowPrefix: 'Proposal',
  proposalNotInBalances: 'Proposal — not in balances until committed',
  shareAccepted: 'Accepted',
  yourShare: 'Your share',
  dispute: 'Dispute',
  accept: 'Accept',
  commitToBalances: 'Commit to balances',
  voidProposal: 'Void proposal',
  disputeReasonTitle: 'Why are you disputing?',
  disputeReasonHint: 'Reason',
  cancel: 'Cancel',
  submit: 'Submit',
  proposeCostAction: 'Propose a cost',
  addExpenseTitle: 'Add expense',
  proposeCostTitle: 'Propose a cost',
  saveExpense: 'Save expense',
  saveProposal: 'Save proposal',
  tripBalancesIn: _mockTripBalancesIn,
  splitEqual: _mockSplitEqual,
  splitSolo: 'All on you (solo)',
  convertedAmountLabel: _mockConvertedAmount,
  fxConversionLocked: 'Conversion locked',
  saveConversion: 'Save conversion',
  fxSourceReceipt: 'Receipt total',
);

const governanceTestLabelsAr = ExpenseGovernanceLabels(
  includedDisputedBy: _mockDisputedByAr,
  includedPendingFrom: _mockPendingFromAr,
  someoneFallback: 'شخص',
  proposalRowPrefix: 'اقتراح',
  proposalNotInBalances: 'اقتراح — غير مدرج في الأرصدة',
  shareAccepted: 'مقبول',
  yourShare: 'حصتك',
  dispute: 'اعتراض',
  accept: 'قبول',
  commitToBalances: 'إدراج في الأرصدة',
  voidProposal: 'إلغاء الاقتراح',
  disputeReasonTitle: 'لماذا تعترض؟',
  disputeReasonHint: 'السبب',
  cancel: 'إلغاء',
  submit: 'إرسال',
  proposeCostAction: 'اقتراح تكلفة',
  addExpenseTitle: 'إضافة مصروف',
  proposeCostTitle: 'اقتراح تكلفة',
  saveExpense: 'حفظ المصروف',
  saveProposal: 'حفظ الاقتراح',
  tripBalancesIn: _mockTripBalancesInAr,
  splitEqual: _mockSplitEqualAr,
  splitSolo: 'عليك وحدك',
  convertedAmountLabel: _mockConvertedAmountAr,
  fxConversionLocked: 'محول مقفل',
  saveConversion: 'حفظ التحويل',
  fxSourceReceipt: 'إجمالي الإيصال',
);

String _mockDisputedBy(String name) => 'included — disputed by $name';
String _mockPendingFrom(String name) => 'included — pending from $name';
String _mockTripBalancesIn(String currency) => 'Trip balances in $currency';
String _mockSplitEqual(int count) => 'Split equally · $count Vamigos';
String _mockConvertedAmount(String currency) => 'Converted amount ($currency)';

String _mockDisputedByAr(String name) => 'مُدرَج — اعتراض من $name';
String _mockPendingFromAr(String name) => 'مُدرَج — قيد الانتظار من $name';
String _mockTripBalancesInAr(String currency) => 'أرصدة الرحلة بـ $currency';
String _mockSplitEqualAr(int count) => 'تقسيم متساوٍ · $count';
String _mockConvertedAmountAr(String currency) => 'المبلغ المحول ($currency)';
