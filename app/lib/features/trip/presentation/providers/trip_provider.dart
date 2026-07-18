import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/trip_remote_datasource.dart';
import '../../data/repositories/trip_repository.dart';
import '../../domain/entities/trip_entity.dart';

final tripRemoteDataSourceProvider = Provider<TripRemoteDataSource>((ref) {
  return TripRemoteDataSource(ref.read(supabaseClientProvider));
});

final tripRepositoryProvider = Provider<TripRepository>((ref) {
  return TripRepository(ref.read(tripRemoteDataSourceProvider));
});

/// Active trips shown on the My Trips screen.
final activeTripsProvider = FutureProvider<List<TripEntity>>((ref) async {
  return ref.read(tripRepositoryProvider).getActiveTrips();
});

/// Past trips shown on the Ride History screen.
final pastTripsProvider = FutureProvider<List<TripEntity>>((ref) async {
  return ref.read(tripRepositoryProvider).getPastTrips();
});

/// Trip lifecycle actions with loading state.
class TripActionNotifier extends StateNotifier<bool> {
  final Ref _ref;

  TripActionNotifier(this._ref) : super(false);

  Future<String?> _run(Future<void> Function() action) async {
    state = true;
    try {
      await action();
      _ref.invalidate(activeTripsProvider);
      _ref.invalidate(pastTripsProvider);
      return null;
    } catch (e) {
      return 'Action failed. Please try again.';
    } finally {
      state = false;
    }
  }

  Future<String?> startRide(String rideId) =>
      _run(() => _ref.read(tripRepositoryProvider).startRide(rideId));

  Future<String?> completeRide(String rideId) =>
      _run(() => _ref.read(tripRepositoryProvider).completeRide(rideId));

  Future<String?> cancelRide(String rideId, {String? reason}) => _run(
      () => _ref.read(tripRepositoryProvider).cancelRide(rideId, reason: reason));

  Future<String?> cancelBooking(String bookingId, {String? reason}) =>
      _run(() => _ref
          .read(tripRepositoryProvider)
          .cancelBooking(bookingId, reason: reason));
}

final tripActionProvider =
    StateNotifierProvider<TripActionNotifier, bool>((ref) {
  return TripActionNotifier(ref);
});
