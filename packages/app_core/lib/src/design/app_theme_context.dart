import 'package:flutter/material.dart';

import 'app_motion.dart';
import 'app_radius_elevation.dart';
import 'app_semantic_colors.dart';
import 'app_spacing.dart';
import 'app_type_scale.dart';

extension VamoThemeContext on BuildContext {
  VamoSemanticColors get vamoColors =>
      Theme.of(this).extension<VamoSemanticColors>()!;

  VamoTypeScale get vamoType =>
      Theme.of(this).extension<VamoTypeScale>()!;

  VamoSpacing get vamoSpace => Theme.of(this).extension<VamoSpacing>()!;

  VamoRadiusElevation get vamoShape =>
      Theme.of(this).extension<VamoRadiusElevation>()!;

  VamoMotion get vamoMotion => Theme.of(this).extension<VamoMotion>()!;
}
