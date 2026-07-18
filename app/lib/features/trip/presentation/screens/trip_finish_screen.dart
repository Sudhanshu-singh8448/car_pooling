import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../payment/presentation/providers/payment_provider.dart';
import '../../domain/entities/trip_entity.dart';

/// Screen 9 — review the completed trip and proceed to payment.
class TripFinishScreen extends ConsumerWidget {
  final TripEntity trip;
  const TripFinishScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ride = trip.ride;
    final fare = trip.booking?.totalFare ?? 0;
    final walletAsync = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Trip Finish'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Center(
              child: walletAsync.when(
                data: (w) => Text(
                  'Wallet: ₹ ${w.balance.toStringAsFixed(0)}',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.primary),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle,
                          size: 48, color: AppColors.success),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Trip Completed!', style: AppTypography.h3),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      DateFormat('EEE, d MMM • h:mm a')
                          .format(ride.departureTime),
                      style: AppTypography.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _row(Icons.trip_origin, AppColors.success, 'Pickup Point',
                        ride.pickup.address),
                    const SizedBox(height: AppSpacing.md),
                    _row(Icons.location_on, AppColors.error, 'Drop Point',
                        ride.destination.address),
                    const Divider(height: AppSpacing.xxxl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Fare', style: AppTypography.labelLarge),
                        Text(
                          '₹ ${fare.toStringAsFixed(0)}',
                          style: AppTypography.h2
                              .copyWith(color: AppColors.primary),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${trip.booking?.seatsBooked ?? 1} seat(s) × ₹ ${ride.farePerSeat.toStringAsFixed(0)}',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () =>
                    context.push(RouteNames.paymentMethod, extra: trip),
                icon: const Icon(Icons.payments_outlined),
                label: Text('Pay ₹ ${fare.toStringAsFixed(0)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.caption),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}
