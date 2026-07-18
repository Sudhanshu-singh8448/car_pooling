import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/ride_entity.dart';

/// Card showing a ride's driver, route, time and fare with a Book button.
class RideCard extends StatelessWidget {
  final RideEntity ride;
  final bool isBooking;
  final VoidCallback onBook;

  const RideCard({
    super.key,
    required this.ride,
    required this.onBook,
    this.isBooking = false,
  });

  @override
  Widget build(BuildContext context) {
    final timeText = DateFormat(
      'EEE, d MMM • h:mm a',
    ).format(ride.departureTime);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Driver row
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
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
                          style: AppTypography.labelMedium.copyWith(
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
                      Text(
                        '${ride.vehicleModel} • ${ride.vehicleRegistration}',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹ ${ride.farePerSeat.toStringAsFixed(0)}',
                      style: AppTypography.h4.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    Text('per seat', style: AppTypography.caption),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            // Route
            _routeRow(
              Icons.trip_origin,
              AppColors.success,
              ride.pickup.address,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 9),
              child: Container(width: 2, height: 14, color: AppColors.border),
            ),
            _routeRow(
              Icons.location_on,
              AppColors.error,
              ride.destination.address,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Time + seats + book
            Row(
              children: [
                const Icon(
                  Icons.schedule,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(child: Text(timeText, style: AppTypography.bodySmall)),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    '${ride.availableSeats} seat${ride.availableSeats == 1 ? '' : 's'} left',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isBooking ? null : onBook,
                child: isBooking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Text('Book Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeRow(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
