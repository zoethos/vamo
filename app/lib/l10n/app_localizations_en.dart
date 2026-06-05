// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

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

/// The translations for English (`en_XA`).
class AppLocalizationsEnXa extends AppLocalizationsEn {
  AppLocalizationsEnXa() : super('en_XA');

  @override
  String get appTitle => '【Vámó·】';

  @override
  String get settingsDevLocaleSection =>
      '【····Dévélópér — lóçálé prévíéw·····】';

  @override
  String get settingsDevLocaleSystem => '【··Sýstém défáúlt···】';

  @override
  String get settingsDevLocaleRtl => '【····RTL prévíéw (Árábíç láýóút)·····】';

  @override
  String get settingsDevLocalePseudo =>
      '【·····Pséúdó-lóçálé (lóng stríngs)·····】';
}
