import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Loads intl date symbols for non-English locales used in the app.
Future<void> initializeVamoDateFormatting() async {
  for (final code in ['en', 'it', 'ar', 'he', 'zh', 'hi', 'ja', 'ru']) {
    await initializeDateFormatting(code, null);
  }
}

/// Locale-aware short date (e.g. Jun 2) for trip/expense surfaces.
String formatShortDate(DateTime date, {String? locale}) {
  return DateFormat.MMMd(locale).format(date.toLocal());
}

/// Locale-aware medium date range label.
String formatMediumDate(DateTime date, {String? locale}) {
  return DateFormat.yMMMd(locale).format(date.toLocal());
}
