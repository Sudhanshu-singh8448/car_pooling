import 'package:equatable/equatable.dart';

/// A single event in the trip lifecycle timeline.
class LifecycleEvent extends Equatable {
  final String id;
  final String rideId;
  final String? bookingId;
  final String event;
  final String? actorId;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const LifecycleEvent({
    required this.id,
    required this.rideId,
    this.bookingId,
    required this.event,
    this.actorId,
    this.metadata,
    required this.createdAt,
  });

  factory LifecycleEvent.fromMap(Map<String, dynamic> map) {
    return LifecycleEvent(
      id: map['id'] as String,
      rideId: map['ride_id'] as String,
      bookingId: map['booking_id'] as String?,
      event: map['event'] as String,
      actorId: map['actor_id'] as String?,
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  /// Human-readable label for the event.
  String get displayLabel {
    switch (event) {
      case 'booking_requested':
        return 'Booking Requested';
      case 'booking_accepted':
        return 'Booking Accepted';
      case 'booking_rejected':
        return 'Booking Rejected';
      case 'booking_status_in_progress':
      case 'ride_status_in_progress':
        return 'Ride Started';
      case 'booking_status_completed':
      case 'ride_status_completed':
        return 'Ride Completed';
      case 'booking_status_payment_pending':
        return 'Payment Pending';
      case 'booking_status_payment_completed':
        return 'Payment Completed';
      case 'feedback_submitted':
        return 'Feedback Submitted';
      case 'early_exit_requested':
        return 'Early Exit Requested';
      case 'early_exit_accepted':
        return 'Early Exit Accepted';
      case 'early_exit_rejected':
        return 'Early Exit Rejected';
      case 'ride_status_cancelled':
        return 'Ride Cancelled';
      case 'booking_status_cancelled':
        return 'Booking Cancelled';
      default:
        return event
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
            .join(' ');
    }
  }

  @override
  List<Object?> get props => [id, event, createdAt];
}
