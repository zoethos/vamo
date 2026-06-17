import '../media/media_metadata.dart';

typedef MediaMetadataResolver =
    Future<MediaCaptureMetadata> Function(String imagePath);

Future<MediaCaptureMetadata> resolveCapturePhotoMetadata({
  required bool tagCaptureLocation,
  required String localPath,
  MediaMetadataResolver resolver = _resolveCapturePhotoMetadata,
}) async {
  if (!tagCaptureLocation) return const MediaCaptureMetadata();
  return resolver(localPath);
}

Future<MediaCaptureMetadata> _resolveCapturePhotoMetadata(String localPath) {
  return resolveMediaMetadata(
    localPath,
    screen: 'capture',
    action: 'read_photo_metadata',
  );
}
