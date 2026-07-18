import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../chat/presentation/screens/chat_screen.dart';
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
            if (!trip.isDriver) _buildDriverCard(context),
            if (trip.isDriver) _buildPassengersCard(context),
            const SizedBox(height: AppSpacing.lg),
            _buildRouteCard(),
            const SizedBox(height: AppSpacing.lg),
            _buildVehicleCard(),
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
                  backgroundColor:
                      AppColors.primaryLight.withValues(alpha: 0.2),
                  backgroundImage: ride.driverAvatar != null
                      ? NetworkImage(ride.driverAvatar!)
                      : null,
                  child: ride.driverAvatar == null
                      ? Text(
                          ride.driverName.isNotEmpty
                              ? ride.driverName[0].toUpperCase()
                              : 'D',
                          style: AppTypography.h4
                              .copyWith(color: AppColors.primary),
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
                        ? () => launchUrl(
                            Uri.parse('tel:${ride.driverPhone}'))
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

  Widget _buildPassengersCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Passengers (${trip.passengers.length})',
                style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.md),
            if (trip.passengers.isEmpty)
              Text('No bookings yet.', style: AppTypography.bodySmall)
            else
              ...trip.passengers.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              AppColors.primaryLight.withValues(alpha: 0.2),
                          child: Text(
                            p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                            style: AppTypography.labelMedium
                                .copyWith(color: AppColors.primary),
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
                        IconButton(
                          onPressed: () => context.push(
                            RouteNames.chat,
                            extra: ChatArgs(
                              bookingId: p.bookingId,
                              peerName: p.name,
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline,
                              size: 20, color: AppColors.primary),
                        ),
                        if (p.phone != null)
                          IconButton(
                            onPressed: () =>
                                launchUrl(Uri.parse('tel:${p.phone}')),
                            icon: const Icon(Icons.call_outlined,
                                size: 20, color: AppColors.primary),
                          ),
                      ],
                    ),
                  )),
          ],
        ),
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
            _infoRow(Icons.trip_origin, AppColors.success, 'Pickup Point',
                ride.pickup.address),
            const SizedBox(height: AppSpacing.md),
            _infoRow(Icons.location_on, AppColors.error, 'Drop Point',
                ride.destination.address),
            const SizedBox(height: AppSpacing.md),
            _infoRow(
              Icons.schedule,
              AppColors.primary,
              'Departure',
              DateFormat('EEEE, d MMMM yyyy • h:mm a')
                  .format(ride.departureTime),
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
                  child: const Icon(Icons.directions_car,
                      color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ride.vehicleModel, style: AppTypography.labelMedium),
                    Text(ride.vehicleRegistration,
                        style: AppTypography.caption),
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
              Text(value,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Actions ----------

  List<Widget> _buildActions(
      BuildContext context, WidgetRef ref, bool isBusy) {
    final ride = trip.ride;
    final actions = <Widget>[];

    void addButton(String label, IconData icon, Color color,
        Future<void> Function() onTap,
        {bool outlined = false}) {
      actions.add(Padding(
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
      ));
    }

    if (trip.isDriver) {
      if (ride.status == 'published') {
        addButton('Start Trip', Icons.play_arrow_rounded, AppColors.success,
            () => _confirmAction(
                  context,
                  ref,
                  title: 'Start Trip',
                  message: 'Start this trip? Passengers will be notified.',
                  action: () =>
                      ref.read(tripActionProvider.notifier).startRide(ride.id),
                ));
        addButton('Cancel Ride', Icons.close_rounded, AppColors.error,
            () => _confirmAction(
                  context,
                  ref,
                  title: 'Cancel Ride',
                  message:
                      'Cancel this ride? All passenger bookings will be cancelled.',
                  action: () => ref
                      .read(tripActionProvider.notifier)
                      .cancelRide(ride.id),
                ),
            outlined: true);
      } else if (ride.status == 'in_progress') {
        addButton(
            'Share Live Location',
            Icons.gps_fixed_rounded,
            AppColors.primary,
            () async => context.push(RouteNames.liveTracking, extra: trip));
        addButton('End Trip', Icons.flag_rounded, AppColors.success,
            () => _confirmAction(
                  context,
                  ref,
                  title: 'End Trip',
                  message:
                      'Complete this trip? Passengers will be asked to pay.',
                  action: () => ref
                      .read(tripActionProvider.notifier)
                      .completeRide(ride.id),
                ));
      }
    } else {
      final bookingStatus = trip.booking!.status;
      if (bookingStatus == 'in_progress' || ride.status == 'in_progress') {
        addButton(
            'Track Ride',
            Icons.location_searching_rounded,
            AppColors.primary,
            () async => context.push(RouteNames.liveTracking, extra: trip));
      }
      if (trip.needsPayment) {
        addButton(
            'Proceed to Payment',
            Icons.payments_outlined,
            AppColors.success,
            () async => context.push(RouteNames.tripFinish, extra: trip));
      }
      if (bookingStatus == 'booked') {
        addButton('Cancel Booking', Icons.close_rounded, AppColors.error,
            () => _confirmAction(
                  context,
                  ref,
                  title: 'Cancel Booking',
                  message: 'Cancel your booking on this ride?',
                  action: () => ref
                      .read(tripActionProvider.notifier)
                      .cancelBooking(trip.booking!.id),
                ),
            outlined: true);
      }
    }
    return actions;
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
              child: const Text('No')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes')),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await action();
    if (error != null) {
      messenger.showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.error));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('$title successful.'),
        backgroundColor: AppColors.success,
      ));
      router.go(RouteNames.myTrips);
    }
  }
}
