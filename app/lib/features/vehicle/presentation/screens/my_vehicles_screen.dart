import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/vehicle_entity.dart';
import '../providers/vehicle_provider.dart';

/// Screen 14 — manage registered vehicles.
class MyVehiclesScreen extends ConsumerWidget {
  const MyVehiclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(myVehiclesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: vehiclesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Could not load vehicles'),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: () => ref.invalidate(myVehiclesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (vehicles) => vehicles.isEmpty
            ? _buildEmptyState(context, ref)
            : ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                itemCount: vehicles.length,
                itemBuilder: (context, index) =>
                    _VehicleCard(vehicle: vehicles[index]),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showVehicleFormSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Vehicle'),
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
                Icons.directions_car_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('No vehicles registered', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add your first vehicle to start offering rides!',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleCard extends ConsumerWidget {
  final VehicleEntity vehicle;
  const _VehicleCard({required this.vehicle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        leading: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: const Icon(Icons.directions_car, color: AppColors.primary),
        ),
        title: Text(vehicle.model, style: AppTypography.labelLarge),
        subtitle: Text(
          '${vehicle.registrationNumber} • ${vehicle.seatingCapacity} seats',
          style: AppTypography.bodySmall,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            final messenger = ScaffoldMessenger.of(context);
            switch (action) {
              case 'edit':
                showVehicleFormSheet(context, ref, existing: vehicle);
              case 'toggle':
                await ref
                    .read(vehicleRepositoryProvider)
                    .updateVehicle(
                      id: vehicle.id,
                      status: vehicle.isActive ? 'inactive' : 'active',
                    );
                ref.invalidate(myVehiclesProvider);
              case 'delete':
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Remove Vehicle'),
                    content: Text('Remove ${vehicle.model}?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    await ref
                        .read(vehicleRepositoryProvider)
                        .deleteVehicle(vehicle.id);
                    ref.invalidate(myVehiclesProvider);
                  } catch (_) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Could not remove vehicle.'),
                      ),
                    );
                  }
                }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(vehicle.isActive ? 'Deactivate' : 'Activate'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Remove', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet form for adding/editing a vehicle.
void showVehicleFormSheet(
  BuildContext context,
  WidgetRef ref, {
  VehicleEntity? existing,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _VehicleFormSheet(existing: existing),
  );
}

class _VehicleFormSheet extends ConsumerStatefulWidget {
  final VehicleEntity? existing;
  const _VehicleFormSheet({this.existing});

  @override
  ConsumerState<_VehicleFormSheet> createState() => _VehicleFormSheetState();
}

class _VehicleFormSheetState extends ConsumerState<_VehicleFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _modelController;
  late final TextEditingController _regController;
  late int _seats;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _modelController = TextEditingController(
      text: widget.existing?.model ?? '',
    );
    _regController = TextEditingController(
      text: widget.existing?.registrationNumber ?? '',
    );
    _seats = widget.existing?.seatingCapacity ?? 4;
  }

  @override
  void dispose() {
    _modelController.dispose();
    _regController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final repo = ref.read(vehicleRepositoryProvider);
      if (widget.existing == null) {
        await repo.addVehicle(
          model: _modelController.text.trim(),
          registrationNumber: _regController.text.trim(),
          seatingCapacity: _seats,
        );
      } else {
        await repo.updateVehicle(
          id: widget.existing!.id,
          model: _modelController.text.trim(),
          seatingCapacity: _seats,
        );
      }
      ref.invalidate(myVehiclesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = e.toString().contains('duplicate')
            ? 'This registration number is already registered.'
            : 'Could not save vehicle. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? 'Edit Vehicle' : 'Add Vehicle',
                style: AppTypography.h3,
              ),
              const SizedBox(height: AppSpacing.xl),
              TextFormField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  hintText: 'e.g. Maruti Suzuki Swift',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                ),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter the vehicle model'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _regController,
                enabled: !isEdit,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Registration Number',
                  hintText: 'e.g. GJ-01-AB-1234',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
                validator: (v) => (v == null || v.trim().length < 4)
                    ? 'Enter a valid registration number'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Seating Capacity', style: AppTypography.labelLarge),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _seats > 1
                            ? () => setState(() => _seats--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        color: AppColors.primary,
                      ),
                      Text('$_seats', style: AppTypography.h4),
                      IconButton(
                        onPressed: _seats < 10
                            ? () => setState(() => _seats++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : Text(isEdit ? 'Save Changes' : 'Add Vehicle'),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
