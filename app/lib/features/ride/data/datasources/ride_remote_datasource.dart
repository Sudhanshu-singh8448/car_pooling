import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/booking_entity.dart';
import '../../domain/entities/location_point.dart';
import '../../domain/entities/ride_entity.dart';

class RideRemoteDataSource {
  final SupabaseClient _client;

  RideRemoteDataSource(this._client);

  /// Publish a new ride (driver).
  Future<RideEntity> publishRide({
    required String vehicleId,
    required LocationPoint pickup,
    required LocationPoint destination,
    required DateTime departureTime,
    required int totalSeats,
    required double farePerSeat,
    String? routePolyline,
    double? distanceKm,
    int? durationMinutes,
    bool isRecurring = false,
    String? recurringDays,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final data = await _client
        .from('rides')
        .insert({
          'driver_id': userId,
          'vehicle_id': vehicleId,
          'pickup_address': pickup.address,
          'pickup_lat': pickup.lat,
          'pickup_lng': pickup.lng,
          'destination_address': destination.address,
          'destination_lat': destination.lat,
          'destination_lng': destination.lng,
          'route_polyline': routePolyline,
          'distance_km': distanceKm,
          'duration_minutes': durationMinutes,
          'departure_time': departureTime.toUtc().toIso8601String(),
          'total_seats': totalSeats,
          'available_seats': totalSeats,
          'fare_per_seat': farePerSeat,
          'is_recurring': isRecurring,
          'recurring_days': recurringDays,
        })
        .select(
          '*, profiles!rides_driver_id_fkey(name, avatar_url, phone), vehicles(model, registration_number)',
        )
        .single();
    return RideEntity.fromMap(data);
  }

  /// Search for matching published rides via the `search_rides` RPC.
  Future<List<RideEntity>> searchRides({
    required LocationPoint pickup,
    required LocationPoint destination,
    required DateTime date,
    required int seats,
    double radiusKm = 5,
  }) async {
    final data = await _client.rpc(
      'search_rides',
      params: {
        'p_pickup_lat': pickup.lat,
        'p_pickup_lng': pickup.lng,
        'p_dest_lat': destination.lat,
        'p_dest_lng': destination.lng,
        'p_date':
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'p_seats': seats,
        'p_radius_km': radiusKm,
      },
    );
    return (data as List)
        .map((r) => RideEntity.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Atomically book a ride via the `book_ride` RPC.
  Future<BookingEntity> bookRide({
    required String rideId,
    required int seats,
  }) async {
    final data = await _client.rpc(
      'book_ride',
      params: {'p_ride_id': rideId, 'p_seats': seats},
    );
    return BookingEntity.fromMap(Map<String, dynamic>.from(data as Map));
  }
}
