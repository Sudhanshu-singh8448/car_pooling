import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../ride/domain/entities/booking_entity.dart';
import '../../../ride/domain/entities/ride_entity.dart';
import '../../domain/entities/lifecycle_entity.dart';
import '../../domain/entities/trip_entity.dart';

const _rideSelect =
    '*, profiles!rides_driver_id_fkey(name, avatar_url, phone), vehicles(model, registration_number)';

class TripRemoteDataSource {
  final SupabaseClient _client;

  TripRemoteDataSource(this._client);

  String get _userId => _client.auth.currentUser!.id;

  /// Active trips where the user is a passenger.
  Future<List<TripEntity>> getPassengerTrips({required bool active}) async {
    final statuses = active
        ? ['pending', 'accepted', 'booked', 'in_progress', 'completed', 'payment_pending']
        : ['payment_completed', 'cancelled', 'rejected'];
    final data = await _client
        .from('bookings')
        .select('*, rides($_rideSelect)')
        .eq('passenger_id', _userId)
        .inFilter('status', statuses)
        .order('created_at', ascending: false);

    return (data as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final ride = RideEntity.fromMap(
        Map<String, dynamic>.from(map['rides'] as Map),
      );
      return TripEntity(
        ride: ride,
        isDriver: false,
        booking: BookingEntity.fromMap(map),
      );
    }).toList();
  }

  /// Trips where the user is the driver.
  Future<List<TripEntity>> getDriverTrips({required bool active}) async {
    final statuses = active
        ? ['published', 'in_progress']
        : ['completed', 'cancelled'];
    final data = await _client
        .from('rides')
        .select(
          '$_rideSelect, bookings(*, profiles!bookings_passenger_id_fkey(name, avatar_url, phone))',
        )
        .eq('driver_id', _userId)
        .eq('is_deleted', false)
        .inFilter('status', statuses)
        .order('departure_time', ascending: false);

    return (data as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final ride = RideEntity.fromMap(map);
      final bookings = (map['bookings'] as List? ?? [])
          .map(
            (b) => TripPassenger.fromMap(Map<String, dynamic>.from(b as Map)),
          )
          .where((p) => p.bookingStatus != 'cancelled')
          .toList();
      return TripEntity(ride: ride, isDriver: true, passengers: bookings);
    }).toList();
  }

  /// Driver starts the trip: ride + all booked bookings → in_progress.
  Future<void> startRide(String rideId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client
        .from('rides')
        .update({'status': 'in_progress', 'updated_at': now})
        .eq('id', rideId);
    await _client
        .from('bookings')
        .update({'status': 'in_progress', 'started_at': now, 'updated_at': now})
        .eq('ride_id', rideId)
        .inFilter('status', ['booked', 'accepted']);
  }

  /// Driver completes the trip: ride → completed, bookings → completed
  /// (awaiting payment).
  Future<void> completeRide(String rideId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client
        .from('rides')
        .update({'status': 'completed', 'updated_at': now})
        .eq('id', rideId);
    await _client
        .from('bookings')
        .update({'status': 'completed', 'completed_at': now, 'updated_at': now})
        .eq('ride_id', rideId)
        .inFilter('status', ['booked', 'accepted', 'in_progress']);
  }

  /// Driver cancels the ride; all active bookings are cancelled too.
  Future<void> cancelRide(String rideId, {String? reason}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client
        .from('rides')
        .update({'status': 'cancelled', 'updated_at': now})
        .eq('id', rideId);
    await _client
        .from('bookings')
        .update({
          'status': 'cancelled',
          'cancelled_at': now,
          'cancellation_reason': reason ?? 'Cancelled by driver',
          'updated_at': now,
        })
        .eq('ride_id', rideId)
        .inFilter('status', ['pending', 'accepted', 'booked', 'in_progress']);
  }

  /// Passenger cancels their booking (seats restored via RPC).
  Future<void> cancelBooking(String bookingId, {String? reason}) async {
    await _client.rpc(
      'cancel_booking',
      params: {'p_booking_id': bookingId, 'p_reason': reason},
    );
  }

  // ---------- Live tracking ----------

  /// Driver broadcasts a GPS point.
  Future<void> publishLocation({
    required String rideId,
    required double latitude,
    required double longitude,
    double? speed,
    double? heading,
  }) async {
    await _client.from('ride_locations').insert({
      'ride_id': rideId,
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed,
      'heading': heading,
    });
  }

  /// Last known location for a ride (before realtime kicks in).
  Future<Map<String, dynamic>?> getLastLocation(String rideId) async {
    final data = await _client
        .from('ride_locations')
        .select()
        .eq('ride_id', rideId)
        .order('recorded_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return data;
  }

  /// Realtime stream of location updates for a ride.
  RealtimeChannel subscribeToLocations(
    String rideId,
    void Function(Map<String, dynamic> location) onLocation,
  ) {
    final channel = _client
        .channel('ride_locations:$rideId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ride_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ride_id',
            value: rideId,
          ),
          callback: (payload) => onLocation(payload.newRecord),
        )
        .subscribe();
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) =>
      _client.removeChannel(channel);

  // ---------- Lifecycle timeline ----------

  /// Fetch lifecycle events for a ride (timeline).
  Future<List<LifecycleEvent>> getLifecycleEvents(String rideId) async {
    final data = await _client
        .from('trip_lifecycle')
        .select()
        .eq('ride_id', rideId)
        .order('created_at', ascending: true);
    return (data as List)
        .map((e) =>
            LifecycleEvent.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ---------- Booking accept / reject (driver) ----------

  /// Driver accepts a pending booking request.
  Future<void> acceptBooking(String bookingId) async {
    await _client.rpc(
      'accept_booking',
      params: {'p_booking_id': bookingId},
    );
  }

  /// Driver rejects a pending booking request.
  Future<void> rejectBooking(String bookingId) async {
    await _client.rpc(
      'reject_booking',
      params: {'p_booking_id': bookingId},
    );
  }

  // ---------- Half ride / early exit ----------

  /// Passenger requests to end the ride early.
  Future<void> requestEarlyExit(String bookingId) async {
    await _client.rpc(
      'request_early_exit',
      params: {'p_booking_id': bookingId},
    );
  }

  /// Driver accepts the early exit and sets a new fare.
  Future<void> acceptEarlyExit({
    required String bookingId,
    required double newFare,
  }) async {
    await _client.rpc(
      'accept_early_exit',
      params: {'p_booking_id': bookingId, 'p_new_fare': newFare},
    );
  }

  /// Driver rejects the early exit; ride continues as normal.
  Future<void> rejectEarlyExit(String bookingId) async {
    await _client.rpc(
      'reject_early_exit',
      params: {'p_booking_id': bookingId},
    );
  }

  /// Passenger ends the ride early. Fare is proportionally reduced
  /// based on how many kilometres of the trip were actually completed.
  /// Requires the SQL function `end_ride_early_auto` to be installed
  /// (see `supabase/feature_fixes.sql`).
  Future<void> endRideEarlyAuto({
    required String bookingId,
    required double completedKm,
  }) async {
    await _client.rpc(
      'end_ride_early_auto',
      params: {
        'p_booking_id': bookingId,
        'p_completed_km': completedKm,
      },
    );
  }
}
