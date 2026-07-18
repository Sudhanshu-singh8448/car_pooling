import 'package:equatable/equatable.dart';
import '../../../ride/domain/entities/booking_entity.dart';
import '../../../ride/domain/entities/ride_entity.dart';

/// A passenger on a driver's ride.
class TripPassenger extends Equatable {
  final String bookingId;
  final String passengerId;
  final String name;
  final String? phone;
  final String? avatarUrl;
  final int seatsBooked;
  final double totalFare;
  final String bookingStatus;

  const TripPassenger({
    required this.bookingId,
    required this.passengerId,
    required this.name,
    this.phone,
    this.avatarUrl,
    required this.seatsBooked,
    required this.totalFare,
    required this.bookingStatus,
  });

  factory TripPassenger.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return TripPassenger(
      bookingId: map['id'] as String,
      passengerId: map['passenger_id'] as String,
      name: profile?['name'] as String? ?? 'Passenger',
      phone: profile?['phone'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
      seatsBooked: (map['seats_booked'] as num).toInt(),
      totalFare: (map['total_fare'] as num).toDouble(),
      bookingStatus: map['status'] as String,
    );
  }

  @override
  List<Object?> get props => [bookingId, bookingStatus];
}

/// A trip as seen by the current user — either as passenger (with their
/// booking) or as driver (with the list of passengers).
class TripEntity extends Equatable {
  final RideEntity ride;
  final bool isDriver;
  final BookingEntity? booking; // set when passenger
  final List<TripPassenger> passengers; // set when driver

  const TripEntity({
    required this.ride,
    required this.isDriver,
    this.booking,
    this.passengers = const [],
  });

  String get displayStatus =>
      isDriver ? ride.status : (booking?.status ?? ride.status);

  bool get isActive => isDriver
      ? (ride.status == 'published' || ride.status == 'in_progress')
      : (booking != null &&
          ['booked', 'in_progress', 'completed', 'payment_pending']
              .contains(booking!.status));

  bool get needsPayment =>
      !isDriver &&
      booking != null &&
      ['completed', 'payment_pending'].contains(booking!.status);

  @override
  List<Object?> get props => [ride, isDriver, booking, passengers];
}
