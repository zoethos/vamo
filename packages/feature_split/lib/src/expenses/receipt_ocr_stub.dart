import 'receipt_ocr_models.dart';

/// Web/desktop stub — OCR unavailable.
bool get receiptOcrSupported => false;

Future<ReceiptParseResult?> scanReceiptImage(String imagePath) async => null;
