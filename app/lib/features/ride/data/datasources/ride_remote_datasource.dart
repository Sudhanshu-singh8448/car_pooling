import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/booking_entity.dart';
import '../../domain/entities/location_point.dart';
import '../../domain/entities/recurring_ride_entity.dart';
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
    int tripsPerWeek = 1,
    DateTime? recurrenceStartDate,
    DateTime? recurrenceEndDate,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final selectedDays = recurringDays
        ?.split(',')
        .map((day) => day.trim())
        .where((day) => day.isNotEmpty)
        .toList();

    if (isRecurring) {
      final data = await _client.rpc(
        'publish_ride_with_recurrence',
        params: {
          'p_vehicle_id': vehicleId,
          'p_pickup_address': pickup.address,
          'p_pickup_lat': pickup.lat,
          'p_pickup_lng': pickup.lng,
          'p_destination_address': destination.address,
          'p_destination_lat': destination.lat,
          'p_destination_lng': destination.lng,
          'p_route_polyline': routePolyline,
          'p_distance_km': distanceKm,
          'p_duration_minutes': durationMinutes,
          'p_departure_time': departureTime.toUtc().toIso8601String(),
          'p_total_seats': totalSeats,
          'p_fare_per_seat': farePerSeat,
          'p_recurrence_days': selectedDays ?? const <String>[],
          'p_trips_per_week': tripsPerWeek,
          'p_start_date': _dateOnly(recurrenceStartDate ?? departureTime),
          'p_end_date': recurrenceEndDate == null
              ? null
              : _dateOnly(recurrenceEndDate),
        },
      );
      return RideEntity.fromMap(Map<String, dynamic>.from(data as Map));
    }

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
          'recurring_days': isRecurring ? recurringDays : null,
        })
        .select(
          '*, profiles!rides_driver_id_fkey(name, avatar_url, phone), vehicles(model, registration_number)',
        )
        .single();
    return RideEntity.fromMap(data);
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Search for matching published rides.
  ///
  /// Uses the `search_rides_v2` RPC: candidates are filtered by a
  /// local-day time window (fixes the old UTC date-mismatch bug) and a
  /// route-corridor bounding box, so midway pickups are included. Falls
  /// back to the legacy `search_rides` RPC if v2 isn't deployed yet.
  Future<List<RideEntity>> searchRides({
    required LocationPoint pickup,
    required LocationPoint destination,
    required DateTime date,
    required int seats,
    double radiusKm = 5,
  }) async {
    // The searcher picked a LOCAL calendar day — convert to a UTC window.
    final localDayStart = DateTime(date.year, date.month, date.day);
    final localDayEnd = localDayStart.add(const Duration(days: 1));

    dynamic data;
    try {
      data = await _client.rpc(
        'search_rides_v2',
        params: {
          'p_pickup_lat': pickup.lat,
          'p_pickup_lng': pickup.lng,
          'p_dest_lat': destination.lat,
          'p_dest_lng': destination.lng,
          'p_start': localDayStart.toUtc().toIso8601String(),
          'p_end': localDayEnd.toUtc().toIso8601String(),
          'p_seats': seats,
          'p_radius_km': radiusKm,
        },
      );
    } on PostgrestException catch (e) {
      // v2 not deployed yet (PGRST202 = function not found) — legacy path.
      if (e.code != 'PGRST202') rethrow;
      data = await _client.rpc(
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
    }
    return (data as List)
        .map((r) => RideEntity.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Request a booking (creates with status 'pending').
  /// The driver must accept/reject before the booking is confirmed.
  Future<BookingEntity> bookRide({
    required String rideId,
    required int seats,
  }) async {
    final data = await _client.rpc(
      'request_booking',
      params: {'p_ride_id': rideId, 'p_seats': seats},
    );
    return BookingEntity.fromMap(Map<String, dynamic>.from(data as Map));
  }

  /// Search recurring rides. Scoring, exact matching, filtering, and
  /// pagination are performed by PostgreSQL.
  Future<List<RecurringRideMatch>> searchRecurringRides({
    required LocationPoint pickup,
    required LocationPoint destination,
    required List<String> days,
    required DateTime date,
    required int seats,
    int? tripsPerWeek,
    double? maxFare,
    String? vehicleId,
    double radiusKm = 5,
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _client.rpc(
      'search_recurring_rides_v2',
      params: {
        'p_pickup_lat': pickup.lat,
        'p_pickup_lng': pickup.lng,
        'p_dest_lat': destination.lat,
        'p_dest_lng': destination.lng,
        'p_days': days,
        'p_date': _dateOnly(date),
        'p_seats': seats,
        'p_trips_per_week': tripsPerWeek,
        'p_radius_km': radiusKm,
        'p_max_fare': maxFare,
        'p_vehicle_id': vehicleId,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return (data as List)
        .map(
          (r) =>
              RecurringRideMatch.fromMap(Map<String, dynamic>.from(r as Map)),
        )
        .toList();
  }

  Future<RecurringRideEntity> upsertRecurringRide({
    required String rideId,
    required List<String> recurrenceDays,
    required int tripsPerWeek,
    required DateTime startDate,
    DateTime? endDate,
    bool isActive = true,
  }) async {
    final data = await _client.rpc(
      'upsert_recurring_ride',
      params: {
        'p_ride_id': rideId,
        'p_recurrence_days': recurrenceDays,
        'p_trips_per_week': tripsPerWeek,
        'p_start_date': _dateOnly(startDate),
        'p_end_date': endDate == null ? null : _dateOnly(endDate),
        'p_is_active': isActive,
      },
    );
    return RecurringRideEntity.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Future<RecurringRideEntity> setRecurringRideActive({
    required String rideId,
    required bool isActive,
  }) async {
    final data = await _client.rpc(
      'set_recurring_ride_active',
      params: {'p_ride_id': rideId, 'p_is_active': isActive},
    );
    return RecurringRideEntity.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Future<void> deleteRecurringRide(String rideId) async {
    await _client.rpc('delete_recurring_ride', params: {'p_ride_id': rideId});
  }

  RealtimeChannel subscribeToRecurringRideChanges(void Function() onChanged) {
    return _client
        .channel('recurring-rides-search')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'recurring_rides',
          callback: (_) => onChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          callback: (_) => onChanged(),
        )
        .subscribe();
  }

  Future<void> unsubscribe(RealtimeChannel channel) =>
      _client.removeChannel(channel);
}
