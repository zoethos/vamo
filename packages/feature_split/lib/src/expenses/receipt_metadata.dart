import '../media/media_metadata.dart';

typedef ReceiptCaptureMetadata = MediaCaptureMetadata;

/// Reads EXIF GPS/timestamp when present; otherwise returns empty metadata.
Future<ReceiptCaptureMetadata> resolveReceiptMetadata(String imagePath) async {
  return resolveMediaMetadata(
    imagePath,
    screen: 'receipt',
    action: 'read_exif_metadata',
  );
}
