import 'package:supabase_flutter/supabase_flutter.dart';

import '../datasources/trip_remote_datasource.dart';
import '../../domain/entities/trip_entity.dart';

class TripRepository {
  final TripRemoteDataSource _dataSource;

  TripRepository(this._dataSource);

  /// All active trips (passenger + driver), sorted by departure time.
  Future<List<TripEntity>> getActiveTrips() async {
    final results = await Future.wait([
      _dataSource.getPassengerTrips(active: true),
      _dataSource.getDriverTrips(active: true),
    ]);
    final trips = [...results[0], ...results[1]];
    trips.sort((a, b) => a.ride.departureTime.compareTo(b.ride.departureTime));
    return trips;
  }

  /// All past trips (payment completed / completed / cancelled).
  Future<List<TripEntity>> getPastTrips() async {
    final results = await Future.wait([
      _dataSource.getPassengerTrips(active: false),
      _dataSource.getDriverTrips(active: false),
    ]);
    final trips = [...results[0], ...results[1]];
    trips.sort((a, b) => b.ride.departureTime.compareTo(a.ride.departureTime));
    return trips;
  }

  Future<void> startRide(String rideId) => _dataSource.startRide(rideId);
  Future<void> completeRide(String rideId) => _dataSource.completeRide(rideId);
  Future<void> cancelRide(String rideId, {String? reason}) =>
      _dataSource.cancelRide(rideId, reason: reason);
  Future<void> cancelBooking(String bookingId, {String? reason}) =>
      _dataSource.cancelBooking(bookingId, reason: reason);

  Future<void> publishLocation({
    required String rideId,
    required double latitude,
    required double longitude,
    double? speed,
    double? heading,
  }) => _dataSource.publishLocation(
    rideId: rideId,
    latitude: latitude,
    longitude: longitude,
    speed: speed,
    heading: heading,
  );

  Future<Map<String, dynamic>?> getLastLocation(String rideId) =>
      _dataSource.getLastLocation(rideId);

  RealtimeChannel subscribeToLocations(
    String rideId,
    void Function(Map<String, dynamic>) onLocation,
  ) => _dataSource.subscribeToLocations(rideId, onLocation);

  Future<void> unsubscribe(RealtimeChannel channel) =>
      _dataSource.unsubscribe(channel);
}
