import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/notification_remote_datasource.dart';
import '../../domain/entities/notification_entity.dart';

// --- DI ---

final notificationDataSourceProvider =
    Provider<NotificationRemoteDataSource>((ref) {
  return NotificationRemoteDataSource(ref.read(supabaseClientProvider));
});

// --- Notifications list ---

final notificationsProvider =
    FutureProvider.autoDispose<List<NotificationEntity>>((ref) async {
  return ref.read(notificationDataSourceProvider).getNotifications();
});

// --- Unread count ---

final unreadCountProvider = StateProvider<int>((ref) => 0);

// --- Realtime notification listener ---

/// Call this once when the dashboard loads to start listening for new
/// notifications and keep the badge count up-to-date.
class NotificationListenerNotifier extends StateNotifier<bool> {
  final Ref _ref;
  RealtimeChannel? _channel;

  NotificationListenerNotifier(this._ref) : super(false);

  Future<void> start() async {
    if (state) return; // already listening
    state = true;

    // Fetch initial unread count
    final count =
        await _ref.read(notificationDataSourceProvider).getUnreadCount();
    _ref.read(unreadCountProvider.notifier).state = count;

    // Subscribe to realtime
    _channel = _ref
        .read(notificationDataSourceProvider)
        .subscribeToNotifications((notification) {
      // Increment badge
      _ref.read(unreadCountProvider.notifier).state++;
      // Invalidate the list so it re-fetches when viewed
      _ref.invalidate(notificationsProvider);
    });
  }

  Future<void> stop() async {
    if (_channel != null) {
      await _ref.read(notificationDataSourceProvider).unsubscribe(_channel!);
      _channel = null;
    }
    state = false;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

final notificationListenerProvider =
    StateNotifierProvider<NotificationListenerNotifier, bool>((ref) {
  return NotificationListenerNotifier(ref);
});

// --- Notification actions ---

class NotificationActionState {
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const NotificationActionState({
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });
}

class NotificationActionNotifier
    extends StateNotifier<NotificationActionState> {
  final Ref _ref;

  NotificationActionNotifier(this._ref)
      : super(const NotificationActionState());

  Future<void> markAsRead(String notificationId) async {
    await _ref
        .read(notificationDataSourceProvider)
        .markAsRead(notificationId);
    final count = _ref.read(unreadCountProvider);
    if (count > 0) {
      _ref.read(unreadCountProvider.notifier).state = count - 1;
    }
    _ref.invalidate(notificationsProvider);
  }

  Future<void> markAllAsRead() async {
    await _ref.read(notificationDataSourceProvider).markAllAsRead();
    _ref.read(unreadCountProvider.notifier).state = 0;
    _ref.invalidate(notificationsProvider);
  }

  Future<void> deleteNotification(String notificationId) async {
    await _ref
        .read(notificationDataSourceProvider)
        .deleteNotification(notificationId);
    _ref.invalidate(notificationsProvider);
  }

  Future<String?> acceptBooking(String bookingId) async {
    state = const NotificationActionState(isLoading: true);
    try {
      await _ref
          .read(notificationDataSourceProvider)
          .acceptBooking(bookingId);
      _ref.invalidate(notificationsProvider);
      state = const NotificationActionState(
          successMessage: 'Booking accepted successfully!');
      return null;
    } catch (e) {
      final msg = _friendlyError(e);
      state = NotificationActionState(errorMessage: msg);
      return msg;
    }
  }

  Future<String?> rejectBooking(String bookingId) async {
    state = const NotificationActionState(isLoading: true);
    try {
      await _ref
          .read(notificationDataSourceProvider)
          .rejectBooking(bookingId);
      _ref.invalidate(notificationsProvider);
      state = const NotificationActionState(
          successMessage: 'Booking rejected.');
      return null;
    } catch (e) {
      final msg = _friendlyError(e);
      state = NotificationActionState(errorMessage: msg);
      return msg;
    }
  }

  static String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('BOOKING_NOT_FOUND')) return 'Booking not found.';
    if (msg.contains('NOT_AUTHORIZED')) return 'You are not authorized.';
    if (msg.contains('BOOKING_NOT_PENDING')) {
      return 'This booking is no longer pending.';
    }
    if (msg.contains('INSUFFICIENT_SEATS')) return 'Not enough seats left.';
    return 'Action failed. Please try again.';
  }
}

final notificationActionProvider =
    StateNotifierProvider<NotificationActionNotifier, NotificationActionState>(
        (ref) {
  return NotificationActionNotifier(ref);
});
