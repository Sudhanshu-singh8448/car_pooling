import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/notification_entity.dart';

class NotificationRemoteDataSource {
  final SupabaseClient _client;

  NotificationRemoteDataSource(this._client);

  String get _userId => _client.auth.currentUser!.id;

  /// Fetch paginated notifications for the current user.
  Future<List<NotificationEntity>> getNotifications({
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _client
        .from('notifications')
        .select()
        .eq('user_id', _userId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((n) =>
            NotificationEntity.fromMap(Map<String, dynamic>.from(n as Map)))
        .toList();
  }

  /// Get count of unread notifications.
  Future<int> getUnreadCount() async {
    final data = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', _userId)
        .eq('is_read', false);
    return (data as List).length;
  }

  /// Mark a single notification as read.
  Future<void> markAsRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', notificationId)
        .eq('user_id', _userId);
  }

  /// Mark all notifications as read.
  Future<void> markAllAsRead() async {
    await _client
        .from('notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', _userId)
        .eq('is_read', false);
  }

  /// Delete a notification.
  Future<void> deleteNotification(String notificationId) async {
    await _client
        .from('notifications')
        .delete()
        .eq('id', notificationId)
        .eq('user_id', _userId);
  }

  /// Accept a pending booking request (driver action).
  Future<void> acceptBooking(String bookingId) async {
    await _client.rpc(
      'accept_booking',
      params: {'p_booking_id': bookingId},
    );
  }

  /// Reject a pending booking request (driver action).
  Future<void> rejectBooking(String bookingId) async {
    await _client.rpc(
      'reject_booking',
      params: {'p_booking_id': bookingId},
    );
  }

  /// Subscribe to new notifications via Supabase Realtime.
  RealtimeChannel subscribeToNotifications(
    void Function(NotificationEntity notification) onNotification,
  ) {
    return _client
        .channel('notifications:$_userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _userId,
          ),
          callback: (payload) =>
              onNotification(NotificationEntity.fromMap(payload.newRecord)),
        )
        .subscribe();
  }

  Future<void> unsubscribe(RealtimeChannel channel) =>
      _client.removeChannel(channel);

  /// Register a device token for push notifications.
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    await _client.from('device_tokens').upsert(
      {
        'user_id': _userId,
        'token': token,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,token',
    );
  }

  /// Remove a device token (on logout).
  Future<void> removeDeviceToken(String token) async {
    await _client
        .from('device_tokens')
        .delete()
        .eq('user_id', _userId)
        .eq('token', token);
  }
}
