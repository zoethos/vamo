/// List row model — sourced from Drift in Slice 1.
class TripSummary {
  const TripSummary({
    required this.id,
    required this.name,
    this.destination,
    this.startDate,
    this.endDate,
    required this.baseCurrency,
  });

  final String id;
  final String name;
  final String? destination;
  final String? startDate;
  final String? endDate;
  final String baseCurrency;
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
  });

  final String id;
  final String name;
  final String? destination;
  final String? startDate;
  final String? endDate;
  final String baseCurrency;
  final String ownerId;
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
