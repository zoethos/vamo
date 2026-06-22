import 'package:app_core/app_core.dart';
import 'package:feature_split/src/plan/plan_models.dart';
import 'package:feature_split/src/plan/plan_type_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plan type visuals use design-system color tokens', () {
    expect(visualForPlanKind(PlanItemKind.visit).accent, AppColors.sunsetCoral);
    expect(
      visualForPlanKind(PlanItemKind.activity).accent,
      AppColors.sunsetCoral,
    );
    expect(visualForPlanKind(PlanItemKind.train).accent, AppColors.jadeTeal);
    expect(visualForPlanKind(PlanItemKind.flight).accent, AppColors.sky);
    expect(visualForPlanKind(PlanItemKind.transfer).accent, AppColors.sunrise);
    expect(visualForPlanKind(PlanItemKind.lodging).accent, AppColors.deepPlum);
    expect(visualForPlanKind(PlanItemKind.other).accent, AppColors.neutralMid);
  });

  test('plan type visuals keep the expected icons', () {
    expect(visualForPlanKind(PlanItemKind.visit).icon, Icons.place_outlined);
    expect(visualForPlanKind(PlanItemKind.train).icon, Icons.train_outlined);
    expect(visualForPlanKind(PlanItemKind.flight).icon, Icons.flight_outlined);
    expect(
      visualForPlanKind(PlanItemKind.transfer).icon,
      Icons.sync_alt_outlined,
    );
    expect(visualForPlanKind(PlanItemKind.lodging).icon, Icons.hotel_outlined);
    expect(
      visualForPlanKind(PlanItemKind.other).icon,
      Icons.event_note_outlined,
    );
  });
}
