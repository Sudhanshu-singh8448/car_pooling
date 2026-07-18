import 'package:equatable/equatable.dart';

class NotificationEntity extends Equatable {
  final String id;
  final String userId;
  final String? senderId;
  final String title;
  final String body;
  final String? type;
  final String category; // booking | ride | payment | chat | system
  final Map<String, dynamic>? data;
  final String? deepLink;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;

  const NotificationEntity({
    required this.id,
    required this.userId,
    this.senderId,
    required this.title,
    required this.body,
    this.type,
    this.category = 'system',
    this.data,
    this.deepLink,
    this.isRead = false,
    required this.createdAt,
    this.readAt,
  });

  factory NotificationEntity.fromMap(Map<String, dynamic> map) {
    return NotificationEntity(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      senderId: map['sender_id'] as String?,
      title: map['title'] as String,
      body: map['body'] as String,
      type: map['type'] as String?,
      category: map['category'] as String? ?? 'system',
      data: map['data'] != null
          ? Map<String, dynamic>.from(map['data'] as Map)
          : null,
      deepLink: map['deep_link'] as String?,
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      readAt: map['read_at'] != null
          ? DateTime.parse(map['read_at'] as String).toLocal()
          : null,
    );
  }

  /// Whether this notification has booking-request actions (accept/reject).
  bool get isBookingRequest => type == 'booking_request';

  /// Extract booking ID from data payload.
  String? get bookingId => data?['booking_id'] as String?;
  String? get rideId => data?['ride_id'] as String?;

  @override
  List<Object?> get props => [id, isRead, type];
}
