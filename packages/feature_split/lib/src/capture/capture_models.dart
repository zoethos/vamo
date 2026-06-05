/// Note for solo trip capture (Slice 8).
class TripNoteView {
  const TripNoteView({
    required this.id,
    required this.tripId,
    required this.title,
    required this.body,
    required this.capturedAt,
  });

  final String id;
  final String tripId;
  final String title;
  final String body;
  final DateTime capturedAt;
}

/// Photo for solo trip capture — local path when cached; [loadError] when remote exists but fetch failed.
class TripPhotoView {
  const TripPhotoView({
    required this.id,
    required this.tripId,
    this.displayPath,
    this.caption,
    required this.capturedAt,
    this.loadError,
    this.hasRemoteStoragePath = false,
    this.storagePath,
  });

  final String id;
  final String tripId;
  final String? displayPath;
  final String? caption;
  final DateTime capturedAt;
  final Object? loadError;
  final bool hasRemoteStoragePath;
  final String? storagePath;
}

/// Highlights for the branded snapshot card.
class CaptureSnapshotHighlight {
  const CaptureSnapshotHighlight({
    this.noteTitle,
    this.noteExcerpt,
    this.photoPaths = const [],
  });

  final String? noteTitle;
  final String? noteExcerpt;
  final List<String> photoPaths;
}

CaptureSnapshotHighlight buildCaptureSnapshotHighlight({
  required List<TripNoteView> notes,
  required List<TripPhotoView> photos,
}) {
  final latest = notes.isNotEmpty ? notes.first : null;
  return CaptureSnapshotHighlight(
    noteTitle: latest?.title,
    noteExcerpt: latest != null ? _noteExcerpt(latest.body) : null,
    photoPaths: photos
        .where((p) => p.displayPath != null)
        .map((p) => p.displayPath!)
        .take(3)
        .toList(),
  );
}

String _noteExcerpt(String body) {
  final t = body.trim();
  if (t.isEmpty) return '';
  if (t.length <= 80) return t;
  return '${t.substring(0, 77)}…';
}
