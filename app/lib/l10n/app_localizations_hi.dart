// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'Vamo';

  @override
  String get settingsDevLocaleSection => 'Developer — locale preview';

  @override
  String get settingsDevLocaleSystem => 'System default';

  @override
  String get settingsDevLocaleRtl => 'RTL preview (Arabic layout)';

  @override
  String get settingsDevLocalePseudo => 'Pseudo-locale (long strings)';
}
