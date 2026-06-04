import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


/// Subscribes to Supabase Realtime while a trip is open; refreshes Drift on change.
final tripRealtimeBindingProvider =
    Provider.family<void, String>((ref, tripId) {
  final subscriber = ref.watch(tripRealtimeSubscriberProvider);
  final coordinator = ref.watch(syncCoordinatorProvider);

  subscriber.subscribe(
    tripId,
    onRefresh: () => coordinator.refreshTrip(tripId),
  );

  ref.onDispose(() => subscriber.unsubscribe(tripId));
});
