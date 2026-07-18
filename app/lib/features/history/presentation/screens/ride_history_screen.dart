import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../trip/presentation/providers/trip_provider.dart';
import '../../../trip/presentation/screens/my_trips_screen.dart';

/// Screen 12 — completed and cancelled trips.
class RideHistoryScreen extends ConsumerWidget {
  const RideHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pastTripsAsync = ref.watch(pastTripsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(pastTripsProvider),
        child: pastTripsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: const [
              SizedBox(height: 120),
              Center(child: Text('Failed to load history. Pull to retry.')),
            ],
          ),
          data: (trips) {
            if (trips.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  const Icon(Icons.history,
                      size: 64, color: AppColors.textTertiary),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: Text('No past rides yet',
                        style: AppTypography.h4
                            .copyWith(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Center(
                    child: Text(
                      'Completed and cancelled trips will appear here.',
                      style: AppTypography.bodySmall,
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              itemCount: trips.length,
              itemBuilder: (context, index) => TripCard(trip: trips[index]),
            );
          },
        ),
      ),
    );
  }
}
