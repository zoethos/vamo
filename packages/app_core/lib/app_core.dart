/// Back-compat umbrella for the app_core package.
///
/// Prefer the layered entry points for new code:
/// - `package:app_core/design.dart`
/// - `package:app_core/domain.dart`
/// - `package:app_core/infra.dart`
///
/// This umbrella is retained so existing `package:app_core/app_core.dart`
/// imports keep compiling while feature slices migrate opportunistically.
library app_core;

export 'design.dart';
export 'domain.dart';
export 'infra.dart';
