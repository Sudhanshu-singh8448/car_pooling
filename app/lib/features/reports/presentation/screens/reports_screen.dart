import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../trip/domain/entities/trip_entity.dart';
import '../../../trip/presentation/providers/trip_provider.dart';

/// Screen 13 — sustainability & financial reports aggregated client-side.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  // Defaults matching org settings seed values.
  static const _fuelCostPerKm = 6.5; // ₹/km driving alone
  static const _co2PerKm = 0.12; // kg CO₂ saved per shared km

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pastTripsAsync = ref.watch(pastTripsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reports'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: pastTripsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Failed to load report data.')),
        data: (trips) {
          final completed = trips
              .where((t) => t.ride.status == 'completed')
              .toList();
          final totalTrips = completed.length;
          final totalKm = completed.fold<double>(
            0,
            (sum, t) => sum + (t.ride.distanceKm ?? 0),
          );
          final totalSpent = completed.fold<double>(
            0,
            (sum, t) => sum + (t.isDriver ? 0 : (t.booking?.totalFare ?? 0)),
          );
          final totalEarned = completed.fold<double>(
            0,
            (sum, t) => !t.isDriver
                ? sum
                : sum + t.passengers.fold<double>(0, (s, p) => s + p.totalFare),
          );
          final fuelSaved = totalKm * _fuelCostPerKm - totalSpent;
          final co2Saved = totalKm * _co2PerKm;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Overview', style: AppTypography.h4),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _statCard(
                      'Total Trips',
                      '$totalTrips',
                      Icons.route_outlined,
                      AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _statCard(
                      'Distance',
                      '${totalKm.toStringAsFixed(0)} km',
                      Icons.straighten,
                      AppColors.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _statCard(
                      'CO₂ Saved',
                      '${co2Saved.toStringAsFixed(1)} kg',
                      Icons.eco_outlined,
                      AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _statCard(
                      'Est. Savings',
                      '₹ ${fuelSaved.clamp(0, double.infinity).toStringAsFixed(0)}',
                      Icons.savings_outlined,
                      AppColors.warning,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text('Trips per Month', style: AppTypography.h4),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: SizedBox(
                      height: 220,
                      child: _MonthlyTripsChart(trips: completed),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text('Financial Summary', style: AppTypography.h4),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      children: [
                        _finRow(
                          'Total spent on rides',
                          '₹ ${totalSpent.toStringAsFixed(0)}',
                        ),
                        const Divider(),
                        _finRow(
                          'Total earned as driver',
                          '₹ ${totalEarned.toStringAsFixed(0)}',
                        ),
                        const Divider(),
                        _finRow(
                          'Estimated solo-drive cost',
                          '₹ ${(totalKm * _fuelCostPerKm).toStringAsFixed(0)}',
                        ),
                        const Divider(),
                        _finRow(
                          'Net savings from carpooling',
                          '₹ ${fuelSaved.clamp(0, double.infinity).toStringAsFixed(0)}',
                          highlight: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: AppSpacing.sm),
              Text(value, style: AppTypography.h3),
              Text(label, style: AppTypography.caption),
            ],
          ),
        ),
      ),
    );
  }

  Widget _finRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: highlight
                ? AppTypography.labelLarge
                : AppTypography.bodyMedium,
          ),
          Text(
            value,
            style: AppTypography.labelLarge.copyWith(
              color: highlight ? AppColors.success : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyTripsChart extends StatelessWidget {
  final List<TripEntity> trips;
  const _MonthlyTripsChart({required this.trips});

  @override
  Widget build(BuildContext context) {
    // Last 6 months buckets.
    final now = DateTime.now();
    final months = List.generate(
      6,
      (i) => DateTime(now.year, now.month - 5 + i),
    );
    final counts = {for (final m in months) '${m.year}-${m.month}': 0};
    for (final trip in trips) {
      final d = trip.ride.departureTime;
      final key = '${d.year}-${d.month}';
      if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
    }
    final maxCount = counts.values.fold<int>(0, (m, v) => v > m ? v : m);

    return BarChart(
      BarChartData(
        maxY: (maxCount + 1).toDouble(),
        barTouchData: BarTouchData(enabled: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (v, _) =>
                  Text(v.toInt().toString(), style: AppTypography.caption),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final index = v.toInt();
                if (index < 0 || index >= months.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('MMM').format(months[index]),
                    style: AppTypography.caption,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(months.length, (i) {
          final m = months[i];
          final count = counts['${m.year}-${m.month}'] ?? 0;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                width: 22,
                borderRadius: BorderRadius.circular(4),
                gradient: AppColors.primaryGradient,
              ),
            ],
          );
        }),
      ),
    );
  }
}
