import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/notification_entity.dart';
import '../providers/notification_provider.dart';

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final actionState = ref.watch(notificationActionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                ref.read(notificationActionProvider.notifier).markAllAsRead(),
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Read all'),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _buildError(ref, e.toString()),
        data: (notifications) {
          if (notifications.isEmpty) {
            return _buildEmpty();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return _NotificationTile(
                  notification: notification,
                  isLoading: actionState.isLoading,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 72,
            color: AppColors.textTertiary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No notifications yet',
            style: AppTypography.h4.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You\'ll see booking requests, ride updates,\nand payment alerts here.',
            textAlign: TextAlign.center,
            style:
                AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildError(WidgetRef ref, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: AppSpacing.md),
          Text('Failed to load notifications',
              style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(error, style: AppTypography.caption),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton.icon(
            onPressed: () => ref.invalidate(notificationsProvider),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final NotificationEntity notification;
  final bool isLoading;

  const _NotificationTile({
    required this.notification,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        color: AppColors.error,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => ref
          .read(notificationActionProvider.notifier)
          .deleteNotification(notification.id),
      child: InkWell(
        onTap: () => _handleTap(context, ref),
        child: Container(
          decoration: BoxDecoration(
            color: notification.isRead
                ? AppColors.surface
                : AppColors.primary.withValues(alpha: 0.04),
            border: Border(
              bottom: BorderSide(
                color: AppColors.divider,
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
            vertical: AppSpacing.lg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIcon(),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: notification.isRead
                                ? AppTypography.labelMedium
                                : AppTypography.labelMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                          ),
                        ),
                        Text(
                          timeago.format(notification.createdAt, locale: 'en_short'),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      notification.body,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (notification.isBookingRequest) ...[
                      const SizedBox(height: AppSpacing.md),
                      _buildBookingActions(context, ref),
                    ],
                  ],
                ),
              ),
              if (!notification.isRead)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: AppSpacing.sm, top: 6),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    final iconData = _iconForType(notification.type);
    final color = _colorForCategory(notification.category);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Icon(iconData, size: 20, color: color),
    );
  }

  Widget _buildBookingActions(BuildContext context, WidgetRef ref) {
    final bookingId = notification.bookingId;
    if (bookingId == null) return const SizedBox.shrink();

    // If this booking was already accepted / rejected in this session,
    // hide the action buttons so the tile feels resolved immediately.
    final handled = ref.watch(handledBookingIdsProvider);
    if (handled.contains(bookingId)) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          'Handled',
          style: AppTypography.caption
              .copyWith(color: AppColors.textTertiary),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: isLoading
                  ? null
                  : () async {
                      final error = await ref
                          .read(notificationActionProvider.notifier)
                          .acceptBooking(bookingId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(error ?? 'Booking accepted! 🎉'),
                            backgroundColor:
                                error != null ? AppColors.error : AppColors.success,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Accept', style: TextStyle(fontSize: 12)),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: SizedBox(
            height: 36,
            child: OutlinedButton.icon(
              onPressed: isLoading
                  ? null
                  : () async {
                      final error = await ref
                          .read(notificationActionProvider.notifier)
                          .rejectBooking(bookingId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(error ?? 'Booking rejected.'),
                            backgroundColor:
                                error != null ? AppColors.error : AppColors.warning,
                          ),
                        );
                      }
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Reject', style: TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ],
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    // Mark as read
    if (!notification.isRead) {
      ref
          .read(notificationActionProvider.notifier)
          .markAsRead(notification.id);
    }
    // Navigate based on deep link. Only a small set of safe routes
    // (that don't require typed `extra` objects) are honoured — anything
    // else falls back to the My Trips screen so we never crash.
    final deepLink = notification.deepLink;
    const safeRoutes = <String>{
      '/my-trips',
      '/wallet',
      '/notifications',
      '/dashboard',
    };
    if (deepLink != null && safeRoutes.contains(deepLink)) {
      context.go(deepLink);
    } else {
      // Any legacy deep link (e.g. /trip-details, /payment-method,
      // /live-tracking) needs a TripEntity we don't have here. Fall
      // back to My Trips where the user can pick the trip.
      context.go('/my-trips');
    }
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'booking_request':
        return Icons.person_add_alt_1_rounded;
      case 'booking_accepted':
        return Icons.check_circle_rounded;
      case 'booking_rejected':
        return Icons.cancel_rounded;
      case 'ride_started':
        return Icons.play_circle_rounded;
      case 'ride_completed':
        return Icons.flag_rounded;
      case 'payment_completed':
        return Icons.payments_rounded;
      case 'feedback_received':
        return Icons.star_rounded;
      case 'early_exit_request':
        return Icons.exit_to_app_rounded;
      case 'early_exit_accepted':
        return Icons.check_rounded;
      case 'early_exit_rejected':
        return Icons.block_rounded;
      case 'chat_message':
        return Icons.chat_bubble_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorForCategory(String category) {
    switch (category) {
      case 'booking':
        return AppColors.primary;
      case 'ride':
        return AppColors.accent;
      case 'payment':
        return AppColors.success;
      case 'chat':
        return AppColors.secondary;
      default:
        return AppColors.info;
    }
  }
}
