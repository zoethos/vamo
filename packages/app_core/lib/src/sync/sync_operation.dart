import 'dart:convert';

/// Outbox operation kinds — remote side executed by [SyncWorker].
enum SyncKind {
  expenseInsert('expense_insert'),
  expenseUpdate('expense_update'),
  placeInsert('place_insert'),
  receiptUpload('receipt_upload'),
  tripPhotoUpload('trip_photo_upload'),
  tripVideoUpload('trip_video_upload'),
  tripBackgroundUpload('trip_background_upload'),
  settlementInsert('settlement_insert'),
  settlementUpdate('settlement_update'),
  tripNoteInsert('trip_note_insert'),
  planItemUpsert('plan_item_upsert'),
  planItemDelete('plan_item_delete'),
  listItemUpsert('list_item_upsert'),
  listItemDelete('list_item_delete');

  const SyncKind(this.value);
  final String value;

  static SyncKind? parse(String raw) {
    for (final k in SyncKind.values) {
      if (k.value == raw) return k;
    }
    return null;
  }

  bool get isMediaUpload =>
      this == receiptUpload ||
      this == tripPhotoUpload ||
      this == tripVideoUpload ||
      this == tripBackgroundUpload;
}

Map<String, dynamic> decodePayload(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

String encodePayload(Map<String, dynamic> payload) => jsonEncode(payload);
