/// Design-system entry point for app_core.
///
/// Import this when a surface needs Vamo tokens, theme helpers, visual
/// primitives, or reusable UI components without pulling in database or network
/// infrastructure.
library app_core_design;

export 'src/categories/category_catalog.dart';
export 'src/categories/category_donut.dart';
export 'src/categories/category_donut_math.dart';
export 'src/design/app_colors.dart';
export 'src/design/app_motion.dart';
export 'src/design/app_radius_elevation.dart';
export 'src/design/app_semantic_colors.dart';
export 'src/design/app_spacing.dart';
export 'src/design/app_states.dart';
export 'src/design/app_theme.dart';
export 'src/design/app_theme_context.dart';
export 'src/design/app_type_scale.dart';
export 'src/design/brand_assets.dart';
export 'src/design/theme_mode_provider.dart';
export 'src/design/vamo_avatar.dart';
export 'src/design/vamo_carousel.dart';
export 'src/design/vamo_circle_icon.dart';
export 'src/design/vamo_date_picker.dart';
export 'src/locale/app_locales.dart';
export 'src/storage/storage_unavailable_placeholder.dart';
export 'src/visual/gradient_scrim.dart';
