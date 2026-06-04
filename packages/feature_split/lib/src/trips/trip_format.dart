import 'package:intl/intl.dart';

/// Formats optional ISO dates for trip subtitles and snapshot cards.
String? formatTripDateRange(String? start, String? end) {
  if (start == null && end == null) return null;
  final fmt = DateFormat.yMMMd();
  try {
    if (start != null && end != null) {
      return '${fmt.format(DateTime.parse(start))} – ${fmt.format(DateTime.parse(end))}';
    }
    if (start != null) return fmt.format(DateTime.parse(start));
    if (end != null) return fmt.format(DateTime.parse(end));
  } catch (_) {
    return null;
  }
  return null;
}
