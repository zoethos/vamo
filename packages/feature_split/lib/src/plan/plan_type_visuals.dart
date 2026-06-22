import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'plan_models.dart';

class PlanTypeVisual {
  const PlanTypeVisual({required this.accent, required this.icon});

  final Color accent;
  final IconData icon;
}

PlanTypeVisual visualForPlanKind(PlanItemKind kind) {
  return switch (kind) {
    PlanItemKind.visit || PlanItemKind.activity => const PlanTypeVisual(
        accent: VamoPlanTypeColors.visit,
        icon: Icons.place_outlined,
      ),
    PlanItemKind.train => const PlanTypeVisual(
        accent: VamoPlanTypeColors.train,
        icon: Icons.train_outlined,
      ),
    PlanItemKind.flight => const PlanTypeVisual(
        accent: VamoPlanTypeColors.flight,
        icon: Icons.flight_outlined,
      ),
    PlanItemKind.transfer => const PlanTypeVisual(
        accent: VamoPlanTypeColors.transfer,
        icon: Icons.sync_alt_outlined,
      ),
    PlanItemKind.lodging => const PlanTypeVisual(
        accent: VamoPlanTypeColors.lodging,
        icon: Icons.hotel_outlined,
      ),
    PlanItemKind.other => const PlanTypeVisual(
        accent: VamoPlanTypeColors.other,
        icon: Icons.event_note_outlined,
      ),
  };
}
