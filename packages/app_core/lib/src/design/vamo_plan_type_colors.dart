import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared plan-type accent tokens.
///
/// Keep these aliases close to [AppColors] so feature surfaces use one
/// vocabulary for Visit, transport, lodging, and uncategorized plan items.
abstract final class VamoPlanTypeColors {
  static const visit = AppColors.sunsetCoral;
  static const train = AppColors.jadeTeal;
  static const flight = AppColors.sky;
  static const transfer = AppColors.sunrise;
  static const lodging = AppColors.deepPlum;
  static const other = AppColors.neutralMid;

  static const all = <Color>[
    visit,
    train,
    flight,
    transfer,
    lodging,
    other,
  ];
}
