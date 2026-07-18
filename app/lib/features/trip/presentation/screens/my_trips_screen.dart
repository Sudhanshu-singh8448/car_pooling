import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/trip_entity.dart';
import '../providers/trip_provider.dart';

/// Screen 8 (list) — active trips as passenger and driver.
class MyTripsScreen extends ConsumerWidget {
  const MyTripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(activeTripsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: tripsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Could not load trips'),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: () => ref.invalidate(activeTripsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (trips) {
          if (trips.isEmpty) return _buildEmptyState(context);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(activeTripsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              itemCount: trips.length,
              itemBuilder: (context, index) =>
                  TripCard(trip: trips[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.route_outlined,
                  size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('No active trips', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Book a ride or offer one to see your trips here.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xxl),
            ElevatedButton(
              onPressed: () => context.go(RouteNames.dashboard),
              child: const Text('Find a Ride'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card for a trip in a list. Also used by Ride History.
class TripCard extends StatelessWidget {
  final TripEntity trip;
  const TripCard({super.key, required this.trip});

  static const _statusColors = {
    'published': AppColors.statusBooked,
    'booked': AppColors.statusBooked,
    'in_progress': AppColors.statusInProgress,
    'completed': AppColors.statusPaymentPending,
    'payment_pending': AppColors.statusPaymentPending,
    'payment_completed': AppColors.statusCompleted,
    'cancelled': AppColors.statusCancelled,
  };

  static const _statusLabels = {
    'published': 'Published',
    'booked': 'Booked',
    'in_progress': 'In Progress',
    'completed': 'Payment Due',
    'payment_pending': 'Payment Due',
    'payment_completed': 'Completed',
    'cancelled': 'Cancelled',
  };

  @override
  Widget build(BuildContext context) {
    final status = trip.displayStatus;
    final color = _statusColors[status] ?? AppColors.textTertiary;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: () => context.push(RouteNames.tripDetails, extra: trip),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: trip.isDriver
                          ? AppColors.secondary.withValues(alpha: 0.1)
                          : AppColors.primary.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      trip.isDriver ? 'DRIVER' : 'PASSENGER',
                      style: AppTypography.caption.copyWith(
                        color: trip.isDriver
                            ? AppColors.secondary
                            : AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      _statusLabels[status] ?? status,
                      style: AppTypography.caption
                          .copyWith(color: color, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Icon(Icons.trip_origin,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(trip.ride.pickup.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  const Icon(Icons.location_on,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(trip.ride.destination.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Icon(Icons.schedule,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('EEE, d MMM • h:mm a')
                        .format(trip.ride.departureTime),
                    style: AppTypography.caption,
                  ),
                  const Spacer(),
                  if (trip.isDriver)
                    Text(
                      '${trip.passengers.length} passenger${trip.passengers.length == 1 ? '' : 's'}',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textSecondary),
                    )
                  else
                    Text(
                      '₹ ${trip.booking!.totalFare.toStringAsFixed(0)}',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.primary),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
