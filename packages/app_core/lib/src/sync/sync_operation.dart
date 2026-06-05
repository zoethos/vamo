import 'dart:convert';

/// Outbox operation kinds — remote side executed by [SyncWorker].
enum SyncKind {
  expenseInsert('expense_insert'),
  expenseUpdate('expense_update'),
  placeInsert('place_insert'),
  receiptUpload('receipt_upload'),
  settlementInsert('settlement_insert'),
  settlementUpdate('settlement_update'),
  tripNoteInsert('trip_note_insert');

  const SyncKind(this.value);
  final String value;

  static SyncKind? parse(String raw) {
    for (final k in SyncKind.values) {
      if (k.value == raw) return k;
    }
    return null;
  }
}

Map<String, dynamic> decodePayload(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

String encodePayload(Map<String, dynamic> payload) => jsonEncode(payload);
