import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/ride_provider.dart';
import '../widgets/ride_card.dart';

/// Screen 7 — list of rides matching the search criteria.
class AvailableRidesScreen extends ConsumerWidget {
  const AvailableRidesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ridesAsync = ref.watch(availableRidesProvider);
    final bookingState = ref.watch(bookingActionProvider);
    final seats = ref.read(rideFormProvider).seats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Rides'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(availableRidesProvider),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ridesAsync.when(
        loading: () => _buildLoadingSkeleton(),
        error: (_, _) => _buildError(ref),
        data: (rides) {
          if (rides.isEmpty) return _buildEmptyState(context, ref);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(availableRidesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              itemCount: rides.length,
              itemBuilder: (context, index) {
                final match = rides[index];
                return RideCard(
                  match: match,
                  isBooking:
                      bookingState.isLoading &&
                      bookingState.bookingRideId == match.ride.id,
                  onBook: () => _bookRide(context, ref, match.ride.id, seats),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _bookRide(
    BuildContext context,
    WidgetRef ref,
    String rideId,
    int seats,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Booking'),
        content: Text('Book $seats seat${seats == 1 ? '' : 's'} on this ride?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Book'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final booking = await ref
        .read(bookingActionProvider.notifier)
        .book(rideId, seats);

    if (booking != null) {
      ref.read(rideFormProvider.notifier).reset();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Ride booked! Check My Trips for details.'),
          backgroundColor: AppColors.success,
        ),
      );
      router.go(RouteNames.myTrips);
    } else {
      final error = ref.read(bookingActionProvider).errorMessage;
      messenger.showSnackBar(
        SnackBar(
          content: Text(error ?? 'Booking failed.'),
          backgroundColor: AppColors.error,
        ),
      );
      ref.invalidate(availableRidesProvider);
    }
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      itemCount: 4,
      itemBuilder: (_, _) => Shimmer.fromColors(
        baseColor: AppColors.surfaceVariant,
        highlightColor: AppColors.surface,
        child: Container(
          height: 220,
          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
        ),
      ),
    );
  }

  Widget _buildError(WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.lg),
          const Text('Could not load rides'),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: () => ref.invalidate(availableRidesProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
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
              child: const Icon(
                Icons.search_off,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('No rides found', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No rides match your criteria.\nTry a different time or date.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xxl),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Modify Search'),
            ),
          ],
        ),
      ),
    );
  }
}
