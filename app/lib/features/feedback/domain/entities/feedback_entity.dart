import 'package:equatable/equatable.dart';

class FeedbackEntity extends Equatable {
  final String id;
  final String rideId;
  final String bookingId;
  final String reviewerId;
  final String revieweeId;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  const FeedbackEntity({
    required this.id,
    required this.rideId,
    required this.bookingId,
    required this.reviewerId,
    required this.revieweeId,
    required this.rating,
    this.comment,
    required this.createdAt,
  });

  factory FeedbackEntity.fromMap(Map<String, dynamic> map) {
    return FeedbackEntity(
      id: map['id'] as String,
      rideId: map['ride_id'] as String,
      bookingId: map['booking_id'] as String,
      reviewerId: map['reviewer_id'] as String,
      revieweeId: map['reviewee_id'] as String,
      rating: map['rating'] as int,
      comment: map['comment'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  @override
  List<Object?> get props => [id, rating];
}
