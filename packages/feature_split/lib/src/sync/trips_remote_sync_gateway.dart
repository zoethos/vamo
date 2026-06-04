import 'package:app_core/app_core.dart';

import '../trips/trips_repository.dart';

/// Bridges [SyncCoordinator] to [TripsRepository] pull methods.
class TripsRemoteSyncGateway implements RemoteSyncGateway {
  TripsRemoteSyncGateway(this._trips);

  final TripsRepository _trips;

  @override
  Future<void> pullAll() => _trips.syncFromRemote();

  @override
  Future<void> pullTrip(String tripId) => _trips.syncTripFromRemote(tripId);
}
