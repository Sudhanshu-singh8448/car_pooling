import 'package:equatable/equatable.dart';
import 'location_point.dart';

class RideEntity extends Equatable {
  final String id;
  final String driverId;
  final String driverName;
  final String? driverAvatar;
  final String? driverPhone;
  final String vehicleId;
  final String vehicleModel;
  final String vehicleRegistration;
  final LocationPoint pickup;
  final LocationPoint destination;
  final String? routePolyline;
  final double? distanceKm;
  final int? durationMinutes;
  final DateTime departureTime;
  final int totalSeats;
  final int availableSeats;
  final double farePerSeat;
  final bool isRecurring;
  final String? recurringDays;
  final String status; // published | in_progress | completed | cancelled

  const RideEntity({
    required this.id,
    required this.driverId,
    required this.driverName,
    this.driverAvatar,
    this.driverPhone,
    required this.vehicleId,
    required this.vehicleModel,
    required this.vehicleRegistration,
    required this.pickup,
    required this.destination,
    this.routePolyline,
    this.distanceKm,
    this.durationMinutes,
    required this.departureTime,
    required this.totalSeats,
    required this.availableSeats,
    required this.farePerSeat,
    this.isRecurring = false,
    this.recurringDays,
    this.status = 'published',
  });

  factory RideEntity.fromMap(Map<String, dynamic> map) {
    // Handles both the flat `search_rides` RPC shape and a joined
    // select (rides + profiles + vehicles) shape.
    final profile = map['profiles'] as Map<String, dynamic>?;
    final vehicle = map['vehicles'] as Map<String, dynamic>?;
    return RideEntity(
      id: map['id'] as String,
      driverId: map['driver_id'] as String,
      driverName:
          map['driver_name'] as String? ?? profile?['name'] as String? ?? '',
      driverAvatar:
          map['driver_avatar'] as String? ?? profile?['avatar_url'] as String?,
      driverPhone:
          map['driver_phone'] as String? ?? profile?['phone'] as String?,
      vehicleId: map['vehicle_id'] as String,
      vehicleModel:
          map['vehicle_model'] as String? ?? vehicle?['model'] as String? ?? '',
      vehicleRegistration:
          map['vehicle_registration'] as String? ??
          vehicle?['registration_number'] as String? ??
          '',
      pickup: LocationPoint(
        address: map['pickup_address'] as String,
        lat: (map['pickup_lat'] as num).toDouble(),
        lng: (map['pickup_lng'] as num).toDouble(),
      ),
      destination: LocationPoint(
        address: map['destination_address'] as String,
        lat: (map['destination_lat'] as num).toDouble(),
        lng: (map['destination_lng'] as num).toDouble(),
      ),
      routePolyline: map['route_polyline'] as String?,
      distanceKm: (map['distance_km'] as num?)?.toDouble(),
      durationMinutes: (map['duration_minutes'] as num?)?.toInt(),
      departureTime: DateTime.parse(map['departure_time'] as String).toLocal(),
      totalSeats: (map['total_seats'] as num).toInt(),
      availableSeats: (map['available_seats'] as num).toInt(),
      farePerSeat: (map['fare_per_seat'] as num).toDouble(),
      isRecurring: map['is_recurring'] as bool? ?? false,
      recurringDays: map['recurring_days'] as String?,
      status: map['status'] as String? ?? 'published',
    );
  }

  @override
  List<Object?> get props => [id, status, availableSeats, departureTime];
}
