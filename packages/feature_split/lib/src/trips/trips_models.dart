/// List row model — sourced from Drift in Slice 1.
class TripSummary {
  const TripSummary({
    required this.id,
    required this.name,
    this.destination,
    this.startDate,
    this.endDate,
    required this.baseCurrency,
    this.lifecycle = 'active',
  });

  final String id;
  final String name;
  final String? destination;
  final String? startDate;
  final String? endDate;
  final String baseCurrency;
  final String lifecycle;
}

/// Trip home header fields.
class TripDetail {
  const TripDetail({
    required this.id,
    required this.name,
    this.destination,
    this.startDate,
    this.endDate,
    required this.baseCurrency,
    required this.ownerId,
    this.lifecycle = 'active',
    this.closeRequestedAt,
  });

  final String id;
  final String name;
  final String? destination;
  final String? startDate;
  final String? endDate;
  final String baseCurrency;
  final String ownerId;
  final String lifecycle;
  final DateTime? closeRequestedAt;
}

class CreateTripInput {
  const CreateTripInput({
    required this.name,
    this.destination,
    this.startDate,
    this.endDate,
    required this.baseCurrency,
  });

  final String name;
  final String? destination;
  final String? startDate;
  final String? endDate;
  final String baseCurrency;
}
