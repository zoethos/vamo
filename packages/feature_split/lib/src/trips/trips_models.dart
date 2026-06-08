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
    this.budgetMode = 'none',
    this.budgetCents,
  });

  final String id;
  final String name;
  final String? destination;
  final String? startDate;
  final String? endDate;
  final String baseCurrency;
  final String lifecycle;
  final String budgetMode;
  final int? budgetCents;
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
    this.budgetMode = 'none',
    this.budgetCents,
    this.backgroundStoragePath,
    this.backgroundLocalPath,
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
  final String budgetMode;
  final int? budgetCents;
  final String? backgroundStoragePath;
  final String? backgroundLocalPath;
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
