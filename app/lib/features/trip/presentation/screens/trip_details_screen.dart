import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../chat/presentation/screens/chat_screen.dart';
import '../../domain/entities/lifecycle_entity.dart';
import '../../domain/entities/trip_entity.dart';
import '../providers/trip_provider.dart';

/// Screen 8 — trip details for passenger or driver.
class TripDetailsScreen extends ConsumerWidget {
  final TripEntity trip;
  const TripDetailsScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBusy = ref.watch(tripActionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Trip Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Booking status badge for passengers
            if (!trip.isDriver && trip.booking != null)
              _buildStatusBadge(trip.booking!.status),
            if (!trip.isDriver) _buildDriverCard(context),
            if (trip.isDriver) _buildPassengersCard(context, ref, isBusy),
            const SizedBox(height: AppSpacing.lg),
            _buildRouteCard(),
            const SizedBox(height: AppSpacing.lg),
            _buildVehicleCard(),
            const SizedBox(height: AppSpacing.lg),
            // Lifecycle timeline
            _LifecycleTimeline(rideId: trip.ride.id),
            const SizedBox(height: AppSpacing.xxl),
            ..._buildActions(context, ref, isBusy),
          ],
        ),
      ),
    );
  }

  // ---------- Cards ----------

  Widget _buildDriverCard(BuildContext context) {
    final ride = trip.ride;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primaryLight.withValues(
                    alpha: 0.2,
                  ),
                  backgroundImage: ride.driverAvatar != null
                      ? NetworkImage(ride.driverAvatar!)
                      : null,
                  child: ride.driverAvatar == null
                      ? Text(
                          ride.driverName.isNotEmpty
                              ? ride.driverName[0].toUpperCase()
                              : 'D',
                          style: AppTypography.h4.copyWith(
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ride.driverName, style: AppTypography.labelLarge),
                      Text('Driver', style: AppTypography.caption),
                    ],
                  ),
                ),
                Text(
                  '₹ ${trip.booking?.totalFare.toStringAsFixed(0) ?? ride.farePerSeat.toStringAsFixed(0)}',
                  style: AppTypography.h4.copyWith(color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: trip.booking != null
                        ? () => context.push(
                            RouteNames.chat,
                            extra: ChatArgs(
                              bookingId: trip.booking!.id,
                              peerName: ride.driverName,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Chat'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: ride.driverPhone != null
                        ? () => launchUrl(Uri.parse('tel:${ride.driverPhone}'))
                        : null,
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('Call'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    IconData icon;
    switch (status) {
      case 'pending':
        color = AppColors.warning;
        label = 'Awaiting Driver Approval';
        icon = Icons.hourglass_top_rounded;
      case 'accepted':
        color = AppColors.success;
        label = 'Booking Accepted';
        icon = Icons.check_circle_rounded;
      case 'rejected':
        color = AppColors.error;
        label = 'Booking Rejected';
        icon = Icons.cancel_rounded;
      case 'in_progress':
        color = AppColors.statusInProgress;
        label = 'Ride In Progress';
        icon = Icons.directions_car_rounded;
      case 'completed':
        color = AppColors.statusCompleted;
        label = 'Ride Completed';
        icon = Icons.flag_rounded;
      case 'payment_completed':
        color = AppColors.success;
        label = 'Payment Done';
        icon = Icons.payments_rounded;
      default:
        color = AppColors.textTertiary;
        label = status.replaceAll('_', ' ').toUpperCase();
        icon = Icons.info_outline;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: AppTypography.labelMedium.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassengersCard(
    BuildContext context,
    WidgetRef ref,
    bool isBusy,
  ) {
    // Separate pending and accepted/booked passengers
    final pending = trip.passengers
        .where((p) => p.bookingStatus == 'pending')
        .toList();
    final confirmed = trip.passengers
        .where((p) => p.bookingStatus != 'pending')
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Passengers (${trip.passengers.length})',
              style: AppTypography.labelLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            if (trip.passengers.isEmpty)
              Text('No bookings yet.', style: AppTypography.bodySmall),
            // Pending requests first
            if (pending.isNotEmpty) ...[
              Text(
                'Pending Requests',
                style: AppTypography.caption.copyWith(color: AppColors.warning),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...pending.map(
                (p) => _buildPassengerTile(
                  context,
                  ref,
                  p,
                  isBusy,
                  isPending: true,
                ),
              ),
              if (confirmed.isNotEmpty) const Divider(height: AppSpacing.xxl),
            ],
            // Confirmed passengers
            ...confirmed.map(
              (p) => _buildPassengerTile(context, ref, p, isBusy),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassengerTile(
    BuildContext context,
    WidgetRef ref,
    TripPassenger p,
    bool isBusy, {
    bool isPending = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryLight.withValues(alpha: 0.2),
                child: Text(
                  p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: AppTypography.labelMedium),
                    Text(
                      '${p.seatsBooked} seat${p.seatsBooked == 1 ? '' : 's'} • ₹ ${p.totalFare.toStringAsFixed(0)}',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              if (!isPending) ...[
                IconButton(
                  onPressed: () => context.push(
                    RouteNames.chat,
                    extra: ChatArgs(bookingId: p.bookingId, peerName: p.name),
                  ),
                  icon: const Icon(
                    Icons.chat_bubble_outline,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                if (p.phone != null)
                  IconButton(
                    onPressed: () => launchUrl(Uri.parse('tel:${p.phone}')),
                    icon: const Icon(
                      Icons.call_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ],
          ),
          // Accept/Reject buttons for pending bookings
          if (isPending) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const SizedBox(width: 44), // offset for avatar
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: isBusy
                          ? null
                          : () async {
                              final error = await ref
                                  .read(tripActionProvider.notifier)
                                  .acceptBooking(p.bookingId);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(error ?? 'Booking accepted!'),
                                    backgroundColor: error != null
                                        ? AppColors.error
                                        : AppColors.success,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text(
                        'Accept',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: OutlinedButton.icon(
                      onPressed: isBusy
                          ? null
                          : () async {
                              final error = await ref
                                  .read(tripActionProvider.notifier)
                                  .rejectBooking(p.bookingId);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(error ?? 'Booking rejected.'),
                                    backgroundColor: error != null
                                        ? AppColors.error
                                        : AppColors.warning,
                                  ),
                                );
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text(
                        'Reject',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRouteCard() {
    final ride = trip.ride;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Route', style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.md),
            _infoRow(
              Icons.trip_origin,
              AppColors.success,
              'Pickup Point',
              ride.pickup.address,
            ),
            const SizedBox(height: AppSpacing.md),
            _infoRow(
              Icons.location_on,
              AppColors.error,
              'Drop Point',
              ride.destination.address,
            ),
            const SizedBox(height: AppSpacing.md),
            _infoRow(
              Icons.schedule,
              AppColors.primary,
              'Departure',
              DateFormat(
                'EEEE, d MMMM yyyy • h:mm a',
              ).format(ride.departureTime),
            ),
            if (ride.distanceKm != null) ...[
              const SizedBox(height: AppSpacing.md),
              _infoRow(
                Icons.route,
                AppColors.secondary,
                'Distance',
                '${ride.distanceKm!.toStringAsFixed(1)} km'
                    '${ride.durationMinutes != null ? ' • ~${ride.durationMinutes} min' : ''}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCard() {
    final ride = trip.ride;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vehicle', style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: const Icon(
                    Icons.directions_car,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ride.vehicleModel, style: AppTypography.labelMedium),
                    Text(
                      ride.vehicleRegistration,
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, Color color, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.caption),
              Text(
                value,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Actions ----------

  List<Widget> _buildActions(BuildContext context, WidgetRef ref, bool isBusy) {
    final ride = trip.ride;
    final actions = <Widget>[];

    void addButton(
      String label,
      IconData icon,
      Color color,
      Future<void> Function() onTap, {
      bool outlined = false,
    }) {
      actions.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: SizedBox(
            height: 50,
            child: outlined
                ? OutlinedButton.icon(
                    onPressed: isBusy ? null : onTap,
                    style: OutlinedButton.styleFrom(foregroundColor: color),
                    icon: Icon(icon, size: 20),
                    label: Text(label),
                  )
                : ElevatedButton.icon(
                    onPressed: isBusy ? null : onTap,
                    style: ElevatedButton.styleFrom(backgroundColor: color),
                    icon: Icon(icon, size: 20),
                    label: Text(label),
                  ),
          ),
        ),
      );
    }

    if (trip.isDriver) {
      if (ride.status == 'published') {
        addButton(
          'Start Trip',
          Icons.play_arrow_rounded,
          AppColors.success,
          () => _confirmAction(
            context,
            ref,
            title: 'Start Trip',
            message: 'Start this trip? Passengers will be notified.',
            action: () =>
                ref.read(tripActionProvider.notifier).startRide(ride.id),
          ),
        );
        addButton(
          'Cancel Ride',
          Icons.close_rounded,
          AppColors.error,
          () => _promptCancellationAndRun(
            context,
            ref,
            title: 'Cancel Ride',
            description:
                'Tell your passengers why this ride is being cancelled.',
            presetReasons: const [
              'Vehicle issue',
              'Personal emergency',
              'Weather / road conditions',
              'Schedule changed',
              'Not enough passengers',
            ],
            action: (reason) => ref
                .read(tripActionProvider.notifier)
                .cancelRide(ride.id, reason: reason),
          ),
          outlined: true,
        );
      } else if (ride.status == 'in_progress') {
        addButton(
          'Share Live Location',
          Icons.gps_fixed_rounded,
          AppColors.primary,
          () async => context.push(RouteNames.liveTracking, extra: trip),
        );
        addButton(
          'End Trip',
          Icons.flag_rounded,
          AppColors.success,
          () => _confirmAction(
            context,
            ref,
            title: 'End Trip',
            message: 'Complete this trip? Passengers will be asked to pay.',
            action: () =>
                ref.read(tripActionProvider.notifier).completeRide(ride.id),
          ),
        );
      }
    } else {
      final bookingStatus = trip.booking!.status;
      if (bookingStatus == 'in_progress' || ride.status == 'in_progress') {
        addButton(
          'Track Ride',
          Icons.location_searching_rounded,
          AppColors.primary,
          () async => context.push(RouteNames.liveTracking, extra: trip),
        );
        // Half ride: end early with proportional fare
        addButton(
          'End Ride Early',
          Icons.exit_to_app_rounded,
          AppColors.warning,
          () => _promptEndEarlyDistance(context, ref, trip),
          outlined: true,
        );
      }
      if (trip.needsPayment) {
        addButton(
          'Proceed to Payment',
          Icons.payments_outlined,
          AppColors.success,
          () async => context.push(RouteNames.tripFinish, extra: trip),
        );
      }
      // Feedback after payment
      if (bookingStatus == 'payment_completed') {
        addButton(
          'Rate Your Driver',
          Icons.star_rounded,
          AppColors.warning,
          () async => context.push(
            RouteNames.feedback,
            extra: {
              'ride_id': ride.id,
              'booking_id': trip.booking!.id,
              'reviewee_id': ride.driverId,
              'reviewee_name': ride.driverName,
            },
          ),
        );
      }
      if (bookingStatus == 'booked' || bookingStatus == 'accepted') {
        addButton(
          'Cancel Booking',
          Icons.close_rounded,
          AppColors.error,
          () => _promptCancellationAndRun(
            context,
            ref,
            title: 'Cancel Booking',
            description: 'Let the driver know why you are cancelling.',
            presetReasons: const [
              'Plans changed',
              'Found another ride',
              'Departure time no longer works',
              'Pickup point too far',
              'Booked by mistake',
            ],
            action: (reason) => ref
                .read(tripActionProvider.notifier)
                .cancelBooking(trip.booking!.id, reason: reason),
          ),
          outlined: true,
        );
      }
    }
    return actions;
  }

  Future<void> _promptEndEarlyDistance(
    BuildContext context,
    WidgetRef ref,
    TripEntity trip,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final fullKm = trip.ride.distanceKm ?? 0.0;
    final fare = trip.booking?.totalFare ?? 0;
    final controller = TextEditingController(
      text: (fullKm > 0 ? fullKm / 2 : 1.0).toStringAsFixed(1),
    );
    final confirmed = await showDialog<double?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('End Ride Early'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How many kilometres of the ${fullKm.toStringAsFixed(1)} km trip have you actually travelled?',
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  suffixText: 'km',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Full fare: ₹${fare.toStringAsFixed(0)}. '
                'You will only be charged for the distance travelled.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final v = double.tryParse(controller.text.trim());
                if (v == null || v <= 0) return;
                Navigator.pop(ctx, v);
              },
              child: const Text('End Ride'),
            ),
          ],
        );
      },
    );
    if (confirmed == null) return;
    final error = await ref
        .read(tripActionProvider.notifier)
        .endRideEarlyAuto(bookingId: trip.booking!.id, completedKm: confirmed);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Ride ended. Please complete payment.')),
      );
    }
  }

  Future<void> _confirmAction(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String message,
    required Future<String?> Function() action,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await action();
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$title successful.'),
          backgroundColor: AppColors.success,
        ),
      );
      router.go(RouteNames.myTrips);
    }
  }

  /// Opens a bottom sheet that lets the user pick a preset cancellation
  /// reason or type a custom one, then runs the [action] with that reason.
  Future<void> _promptCancellationAndRun(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String description,
    required List<String> presetReasons,
    required Future<String?> Function(String reason) action,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _CancellationReasonSheet(
        title: title,
        description: description,
        presetReasons: presetReasons,
      ),
    );

    if (reason == null) return; // user dismissed
    final error = await action(reason);
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$title successful.'),
          backgroundColor: AppColors.success,
        ),
      );
      router.go(RouteNames.myTrips);
    }
  }
}

class _CancellationReasonSheet extends StatefulWidget {
  final String title;
  final String description;
  final List<String> presetReasons;
  static const _otherOption = 'Other';

  const _CancellationReasonSheet({
    required this.title,
    required this.description,
    required this.presetReasons,
  });

  @override
  State<_CancellationReasonSheet> createState() =>
      _CancellationReasonSheetState();
}

class _CancellationReasonSheetState extends State<_CancellationReasonSheet> {
  String? _selected;
  final TextEditingController _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  bool get _isOther => _selected == _CancellationReasonSheet._otherOption;

  bool get _canSubmit {
    if (_selected == null) return false;
    if (_isOther) return _customController.text.trim().isNotEmpty;
    return true;
  }

  void _submit() {
    final reason = _isOther ? _customController.text.trim() : (_selected ?? '');
    if (reason.isEmpty) return;
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final options = [
      ...widget.presetReasons,
      _CancellationReasonSheet._otherOption,
    ];

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: bottomInset + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(widget.title, style: AppTypography.h4),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.description,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ...options.map(
              (option) => RadioGroup<String>(
                groupValue: _selected,
                onChanged: (v) => setState(() => _selected = v),
                child: RadioListTile<String>(
                  value: option,
                  title: Text(option, style: AppTypography.bodyMedium),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: AppColors.primary,
                ),
              ),
            ),
            if (_isOther) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _customController,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Tell us more',
                  hintText: 'Type your reason...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Keep it'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    onPressed: _canSubmit ? _submit : null,
                    child: const Text('Confirm cancel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lifecycle timeline showing all trip events as a vertical stepper.
class _LifecycleTimeline extends ConsumerWidget {
  final String rideId;
  const _LifecycleTimeline({required this.rideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(lifecycleEventsProvider(rideId));
    return eventsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (events) {
        if (events.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trip Timeline', style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.md),
                ...List.generate(events.length, (i) {
                  final event = events[i];
                  final isLast = i == events.length - 1;
                  return _buildTimelineStep(event, isLast);
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimelineStep(LifecycleEvent event, bool isLast) {
    final color = _colorForEvent(event.event);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: AppColors.border)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.displayLabel,
                    style: AppTypography.labelMedium.copyWith(color: color),
                  ),
                  Text(
                    timeago.format(event.createdAt),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForEvent(String event) {
    if (event.contains('requested') || event.contains('pending')) {
      return AppColors.warning;
    } else if (event.contains('accepted') || event.contains('completed')) {
      return AppColors.success;
    } else if (event.contains('rejected') || event.contains('cancelled')) {
      return AppColors.error;
    } else if (event.contains('in_progress') || event.contains('started')) {
      return AppColors.statusInProgress;
    } else if (event.contains('payment')) {
      return AppColors.primary;
    } else if (event.contains('feedback')) {
      return Colors.amber;
    } else if (event.contains('early_exit')) {
      return AppColors.accent;
    }
    return AppColors.info;
  }
}
