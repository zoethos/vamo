import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_ocr_models.dart';
import 'receipt_ocr_parse.dart';

bool get receiptOcrSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

Future<ReceiptParseResult?> scanReceiptImage(String imagePath) async {
  if (!receiptOcrSupported) return null;

  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final image = InputImage.fromFilePath(imagePath);
    final recognized = await recognizer.processImage(image);
    final text = recognized.text.trim();
    if (text.isEmpty) return null;
    return receiptParse(text);
  } finally {
    await recognizer.close();
  }
}
