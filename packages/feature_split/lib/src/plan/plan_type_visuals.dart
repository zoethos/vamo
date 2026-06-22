import 'package:flutter/material.dart';

import 'plan_models.dart';

const _visitCoral = Color(0xFFFF5B4D);
const _trainTeal = Color(0xFF00C2A8);
const _flightCyan = Color(0xFF21B7D7);
const _transferOrange = Color(0xFFFF8A3D);
const _lodgingPurple = Color(0xFF6A2D6F);
const _otherGray = Color(0xFF949AA6);

class PlanTypeVisual {
  const PlanTypeVisual({required this.accent, required this.icon});

  final Color accent;
  final IconData icon;
}

PlanTypeVisual visualForPlanKind(PlanItemKind kind) {
  return switch (kind) {
    PlanItemKind.visit || PlanItemKind.activity => const PlanTypeVisual(
      accent: _visitCoral,
      icon: Icons.place_outlined,
    ),
    PlanItemKind.train => const PlanTypeVisual(
      accent: _trainTeal,
      icon: Icons.train_outlined,
    ),
    PlanItemKind.flight => const PlanTypeVisual(
      accent: _flightCyan,
      icon: Icons.flight_outlined,
    ),
    PlanItemKind.transfer => const PlanTypeVisual(
      accent: _transferOrange,
      icon: Icons.sync_alt_outlined,
    ),
    PlanItemKind.lodging => const PlanTypeVisual(
      accent: _lodgingPurple,
      icon: Icons.hotel_outlined,
    ),
    PlanItemKind.other => const PlanTypeVisual(
      accent: _otherGray,
      icon: Icons.event_note_outlined,
    ),
  };
}
