import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_models.dart';
import 'capture_repository.dart';

final tripNotesProvider =
    StreamProvider.family<List<TripNoteView>, String>((ref, tripId) {
  return ref.watch(captureRepositoryProvider).watchTripNotes(tripId);
});

final tripPhotosProvider =
    StreamProvider.family<List<TripPhotoView>, String>((ref, tripId) {
  return ref.watch(captureRepositoryProvider).watchTripPhotos(tripId);
});

final tripVideosProvider =
    StreamProvider.family<List<TripVideoView>, String>((ref, tripId) {
  return ref.watch(captureRepositoryProvider).watchTripVideos(tripId);
});

final captureSnapshotHighlightProvider =
    Provider.family<CaptureSnapshotHighlight, String>((ref, tripId) {
  final notes = ref.watch(tripNotesProvider(tripId)).valueOrNull ?? [];
  final photos = ref.watch(tripPhotosProvider(tripId)).valueOrNull ?? [];
  return buildCaptureSnapshotHighlight(notes: notes, photos: photos);
});
