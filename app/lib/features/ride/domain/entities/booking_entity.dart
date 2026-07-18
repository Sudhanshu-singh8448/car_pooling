import 'package:equatable/equatable.dart';

class BookingEntity extends Equatable {
  final String id;
  final String rideId;
  final String passengerId;
  final int seatsBooked;
  final double totalFare;
  final String
  status; // booked | in_progress | completed | cancelled | payment_pending | payment_completed
  final DateTime bookedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  const BookingEntity({
    required this.id,
    required this.rideId,
    required this.passengerId,
    required this.seatsBooked,
    required this.totalFare,
    required this.status,
    required this.bookedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancellationReason,
  });

  factory BookingEntity.fromMap(Map<String, dynamic> map) {
    return BookingEntity(
      id: map['id'] as String,
      rideId: map['ride_id'] as String,
      passengerId: map['passenger_id'] as String,
      seatsBooked: (map['seats_booked'] as num).toInt(),
      totalFare: (map['total_fare'] as num).toDouble(),
      status: map['status'] as String,
      bookedAt: DateTime.parse(map['booked_at'] as String).toLocal(),
      startedAt: map['started_at'] != null
          ? DateTime.parse(map['started_at'] as String).toLocal()
          : null,
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String).toLocal()
          : null,
      cancelledAt: map['cancelled_at'] != null
          ? DateTime.parse(map['cancelled_at'] as String).toLocal()
          : null,
      cancellationReason: map['cancellation_reason'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, rideId, status];
}
