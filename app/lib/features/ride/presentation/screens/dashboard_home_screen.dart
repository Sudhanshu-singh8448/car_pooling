import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../vehicle/presentation/providers/vehicle_provider.dart';
import '../providers/ride_provider.dart';
import '../widgets/location_input.dart';
import '../widgets/seat_selector.dart';

/// Dashboard home: Find Ride / Offer Ride tabs (Screen 4 & 5).
class DashboardHomeScreen extends ConsumerStatefulWidget {
  const DashboardHomeScreen({super.key});

  @override
  ConsumerState<DashboardHomeScreen> createState() =>
      _DashboardHomeScreenState();
}

class _DashboardHomeScreenState extends ConsumerState<DashboardHomeScreen> {
  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  final _fareController = TextEditingController();

  @override
  void dispose() {
    _fareController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(rideFormProvider);
    final userName = ref.watch(authNotifierProvider).user?.name ?? 'there';
    final isOffer = form.mode == RideMode.offer;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, ${userName.split(' ').first} 👋',
            style: AppTypography.h2,
          ),
          const SizedBox(height: 4),
          Text(
            isOffer
                ? 'Share your ride with colleagues'
                : 'Where are you going today?',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xxl),
          _buildModeToggle(form),
          const SizedBox(height: AppSpacing.xxl),
          _buildLocationSection(form),
          const SizedBox(height: AppSpacing.lg),
          _buildDateTimePicker(form),
          const SizedBox(height: AppSpacing.lg),
          _buildSeatsRow(form, isOffer),
          if (isOffer) ...[
            const SizedBox(height: AppSpacing.lg),
            _buildFareField(),
            const SizedBox(height: AppSpacing.lg),
            _buildVehicleSelector(form),
          ] else ...[
            const SizedBox(height: AppSpacing.lg),
            _buildRecurringSection(form),
          ],
          const SizedBox(height: AppSpacing.xxl),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => _onSubmit(form),
              icon: Icon(isOffer ? Icons.publish_rounded : Icons.search),
              label: Text(isOffer ? 'Publish Ride' : 'Find Ride'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle(RideFormState form) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          _modeTab('Find Ride', Icons.search, RideMode.find, form.mode),
          _modeTab(
            'Offer Ride',
            Icons.directions_car_outlined,
            RideMode.offer,
            form.mode,
          ),
        ],
      ),
    );
  }

  Widget _modeTab(
    String label,
    IconData icon,
    RideMode mode,
    RideMode current,
  ) {
    final isActive = mode == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(rideFormProvider.notifier).setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? AppColors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: isActive ? AppColors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationSection(RideFormState form) {
    final notifier = ref.read(rideFormProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              LocationInput(
                label: 'Start Location',
                icon: Icons.trip_origin,
                iconColor: AppColors.success,
                value: form.pickup,
                onSelected: notifier.setPickup,
              ),
              const SizedBox(height: AppSpacing.md),
              LocationInput(
                label: 'Destination Location',
                icon: Icons.location_on,
                iconColor: AppColors.error,
                value: form.destination,
                onSelected: notifier.setDestination,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        IconButton(
          onPressed: notifier.swapLocations,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          ),
          icon: const Icon(Icons.swap_vert, color: AppColors.primary),
          tooltip: 'Swap locations',
        ),
      ],
    );
  }

  Widget _buildDateTimePicker(RideFormState form) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: form.departureTime,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 60)),
        );
        if (date == null || !mounted) return;
        if (!context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(form.departureTime),
        );
        if (time == null) return;
        ref
            .read(rideFormProvider.notifier)
            .setDepartureTime(
              DateTime(date.year, date.month, date.day, time.hour, time.minute),
            );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              DateFormat('EEE, d MMM yyyy • h:mm a').format(form.departureTime),
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeatsRow(RideFormState form, bool isOffer) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          isOffer ? 'Available Seats' : 'Seats Needed',
          style: AppTypography.labelLarge,
        ),
        SeatSelector(
          value: form.seats,
          onChanged: (v) => ref.read(rideFormProvider.notifier).setSeats(v),
        ),
      ],
    );
  }

  Widget _buildFareField() {
    return TextField(
      controller: _fareController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (v) =>
          ref.read(rideFormProvider.notifier).setFare(double.tryParse(v) ?? 0),
      decoration: const InputDecoration(
        labelText: 'Fare per Seat (₹)',
        prefixIcon: Icon(Icons.currency_rupee),
        hintText: 'e.g. 120',
      ),
    );
  }

  Widget _buildVehicleSelector(RideFormState form) {
    final vehiclesAsync = ref.watch(myVehiclesProvider);
    return vehiclesAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text(
        'Could not load vehicles.',
        style: AppTypography.bodySmall.copyWith(color: AppColors.error),
      ),
      data: (vehicles) {
        final active = vehicles.where((v) => v.isActive).toList();
        if (active.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'You need a registered vehicle to offer a ride.',
                    style: AppTypography.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(RouteNames.myVehicle),
                  child: const Text('Add'),
                ),
              ],
            ),
          );
        }
        // Auto-select the first vehicle if none chosen
        final selectedId = active.any((v) => v.id == form.vehicleId)
            ? form.vehicleId
            : active.first.id;
        if (selectedId != form.vehicleId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(rideFormProvider.notifier).setVehicle(selectedId!);
            }
          });
        }
        return DropdownButtonFormField<String>(
          initialValue: selectedId,
          decoration: const InputDecoration(
            labelText: 'Vehicle',
            prefixIcon: Icon(Icons.directions_car_outlined),
          ),
          items: active
              .map(
                (v) => DropdownMenuItem(
                  value: v.id,
                  child: Text('${v.model} (${v.registrationNumber})'),
                ),
              )
              .toList(),
          onChanged: (id) {
            if (id != null) {
              ref.read(rideFormProvider.notifier).setVehicle(id);
            }
          },
        );
      },
    );
  }

  Widget _buildRecurringSection(RideFormState form) {
    final notifier = ref.read(rideFormProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recurring Ride', style: AppTypography.labelLarge),
            Switch(
              value: form.isRecurring,
              onChanged: (_) => notifier.toggleRecurring(),
            ),
          ],
        ),
        if (form.isRecurring) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: _weekdays.map((day) {
              final selected = form.recurringDays.contains(day);
              return FilterChip(
                label: Text(
                  day,
                  style: AppTypography.caption.copyWith(
                    color: selected ? AppColors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                selected: selected,
                selectedColor: AppColors.primary,
                showCheckmark: false,
                onSelected: (_) => notifier.toggleRecurringDay(day),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  void _onSubmit(RideFormState form) {
    final messenger = ScaffoldMessenger.of(context);
    if (!form.isValid) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please select both start and destination locations.'),
        ),
      );
      return;
    }
    if (form.departureTime.isBefore(DateTime.now())) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Departure time must be in the future.')),
      );
      return;
    }
    if (form.mode == RideMode.offer) {
      if (form.vehicleId == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Please add a vehicle before offering a ride.'),
          ),
        );
        return;
      }
      if (form.farePerSeat <= 0) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Please enter a fare per seat.')),
        );
        return;
      }
    }
    context.push(RouteNames.routeConfirmation);
  }
}
