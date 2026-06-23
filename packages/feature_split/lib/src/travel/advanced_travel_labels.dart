import 'travel_leg.dart';

/// Localized copy for the Advanced Travel Planning section on New Trip.
class AdvancedTravelLabels {
  const AdvancedTravelLabels({
    required this.toggleTitle,
    required this.toggleBadge,
    required this.toggleSubtitle,
    required this.legsSectionTitle,
    required this.legsInOrder,
    required this.addLeg,
    required this.noLegs,
    required this.draftWithAi,
    required this.draftWithAiBadge,
    required this.draftComingSoon,
    required this.planItMyself,
    required this.aiFootnote,
    required this.legEditorTitle,
    required this.removeLeg,
    required this.modeSectionTitle,
    required this.windowSectionTitle,
    required this.windowAnyTime,
    required this.windowOptionalHint,
    required this.reachSectionTitle,
    required this.reachDistance,
    required this.reachTime,
    required this.reachNoLimit,
    required this.reachDistanceCaption,
    required this.reachTimeCaption,
    required this.reachHoursUnit,
    required this.unitsFootnote,
    required this.saveLeg,
    required this.modeCar,
    required this.modeMotorbike,
    required this.modeBike,
    required this.modeTrain,
    required this.modeFlight,
    required this.modeBus,
    required this.reviewTitle,
    required this.reviewSubtitle,
    required this.reviewWarningsTitle,
    required this.reviewQuestionsTitle,
    required this.reviewAddToPlan,
    required this.reviewSkip,
    required this.reviewCommitting,
    required this.reviewEmpty,
    required this.draftGatedMessage,
    required this.draftFailedMessage,
  });

  final String toggleTitle;
  final String toggleBadge;
  final String toggleSubtitle;
  final String legsSectionTitle;
  final String legsInOrder;
  final String addLeg;
  final String noLegs;
  final String draftWithAi;
  final String draftWithAiBadge;
  final String draftComingSoon;
  final String planItMyself;
  final String aiFootnote;
  final String legEditorTitle;
  final String removeLeg;
  final String modeSectionTitle;
  final String windowSectionTitle;
  final String windowAnyTime;
  final String windowOptionalHint;
  final String reachSectionTitle;
  final String reachDistance;
  final String reachTime;
  final String reachNoLimit;
  final String reachDistanceCaption;
  final String reachTimeCaption;
  final String reachHoursUnit;
  final String unitsFootnote;
  final String saveLeg;
  final String modeCar;
  final String modeMotorbike;
  final String modeBike;
  final String modeTrain;
  final String modeFlight;
  final String modeBus;

  // Draft-route review (Slice 3).
  final String reviewTitle;
  final String reviewSubtitle;
  final String reviewWarningsTitle;
  final String reviewQuestionsTitle;
  final String reviewAddToPlan;
  final String reviewSkip;
  final String reviewCommitting;
  final String reviewEmpty;
  final String draftGatedMessage;
  final String draftFailedMessage;

  String modeLabel(TravelMode mode) => switch (mode) {
        TravelMode.car => modeCar,
        TravelMode.motorbike => modeMotorbike,
        TravelMode.bike => modeBike,
        TravelMode.train => modeTrain,
        TravelMode.flight => modeFlight,
        TravelMode.bus => modeBus,
      };
}
