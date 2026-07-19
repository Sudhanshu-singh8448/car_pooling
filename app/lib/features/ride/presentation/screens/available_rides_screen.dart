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
    final form = ref.watch(rideFormProvider);
    // When the user has toggled "Recurring" and picked at least one day
    // we show the recurring-suggestions view instead of the regular list.
    if (form.isRecurring && form.recurringDays.isNotEmpty) {
      return const _RecurringRidesView();
    }
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

/// Recurring-ride suggestions grouped into "Exact Matches" (all requested
/// weekdays present) and "Other Suggested Matches" (partial overlap).
class _RecurringRidesView extends ConsumerWidget {
  const _RecurringRidesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recurringRidesProvider);
    final form = ref.watch(rideFormProvider);
    final seats = form.seats;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Rides'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(recurringRidesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text('Failed to load recurring rides: $e'),
          ),
        ),
        data: (rides) {
          if (rides.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.event_repeat_outlined,
                        size: 64, color: AppColors.textTertiary),
                    const SizedBox(height: AppSpacing.md),
                    Text('No recurring rides found',
                        style: AppTypography.h4),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Nobody is running a matching weekly ride yet. '
                      'Try loosening the days or check back later.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }
          final exact =
              rides.where((r) => r['is_exact_match'] == true).toList();
          final suggested = rides
              .where((r) => r['is_exact_match'] != true)
              .toList()
            ..sort((a, b) => (b['match_count'] as int? ?? 0)
                .compareTo(a['match_count'] as int? ?? 0));
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(recurringRidesProvider),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                if (exact.isNotEmpty) ...[
                  Text('Exact Matches', style: AppTypography.h4),
                  const SizedBox(height: AppSpacing.sm),
                  ...exact.map((r) => _RecurringCard(data: r, seats: seats)),
                  const SizedBox(height: AppSpacing.lg),
                ] else ...[
                  Text('No Exact Matches Found', style: AppTypography.h4),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (suggested.isNotEmpty) ...[
                  Text('Other Suggested Matches',
                      style: AppTypography.labelLarge),
                  const SizedBox(height: AppSpacing.sm),
                  ...suggested
                      .map((r) => _RecurringCard(data: r, seats: seats)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RecurringCard extends ConsumerWidget {
  final Map<String, dynamic> data;
  final int seats;
  const _RecurringCard({required this.data, required this.seats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(bookingActionProvider);
    final rideId = data['ride_id'] as String;
    final days = (data['recurring_days'] as String? ?? '')
        .split(',')
        .where((d) => d.isNotEmpty)
        .toList();
    final fare = (data['fare_per_seat'] as num?)?.toDouble() ?? 0;
    final matchCount = data['match_count'] as int? ?? 0;
    final total = data['total_requested'] as int? ?? 0;
    final isExact = data['is_exact_match'] == true;
    final isBooking = booking.isLoading && booking.bookingRideId == rideId;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${data['driver_name'] ?? 'Driver'} • '
                    '${data['vehicle_model'] ?? ''}',
                    style: AppTypography.labelLarge,
                  ),
                ),
                if (isExact)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Exact',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.success)),
                  )
                else
                  Text('$matchCount / $total days',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('${data['pickup_address'] ?? ''}  →  '
                '${data['destination_address'] ?? ''}',
                style: AppTypography.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 4,
              children: days
                  .map((d) => Chip(
                        label: Text(d.substring(0, 3).toUpperCase(),
                            style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Text('₹${fare.toStringAsFixed(0)}/seat',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.primary)),
                const Spacer(),
                ElevatedButton(
                  onPressed: isBooking
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final b = await ref
                              .read(bookingActionProvider.notifier)
                              .book(rideId, seats);
                          if (context.mounted) {
                            messenger.showSnackBar(SnackBar(
                              content: Text(b == null
                                  ? (ref
                                          .read(bookingActionProvider)
                                          .errorMessage ??
                                      'Booking failed')
                                  : 'Booking requested!'),
                            ));
                          }
                        },
                  child: isBooking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Request'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
