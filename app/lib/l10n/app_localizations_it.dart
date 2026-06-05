// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Vamo';

  @override
  String get settingsDevLocaleSection => 'Sviluppatore — anteprima lingua';

  @override
  String get settingsDevLocaleSystem => 'Predefinito di sistema';

  @override
  String get settingsDevLocaleRtl => 'Anteprima RTL (layout arabo)';

  @override
  String get settingsDevLocalePseudo => 'Pseudo-locale (stringhe lunghe)';
}
