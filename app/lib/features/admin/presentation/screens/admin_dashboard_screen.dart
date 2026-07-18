import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/admin_provider.dart';

/// Screen 15 — admin dashboard (desktop web layout: wide container,
/// top tabs, data tables).
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(adminStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Employees', icon: Icon(Icons.people_outline, size: 18)),
            Tab(
              text: 'Vehicles',
              icon: Icon(Icons.directions_car_outlined, size: 18),
            ),
            Tab(text: 'Settings', icon: Icon(Icons.tune, size: 18)),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: stats.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (s) => Row(
                    children: [
                      _statCard(
                        'Total Employees',
                        '${s.totalEmployees}',
                        Icons.people_outline,
                        AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      _statCard(
                        'Registered Vehicles',
                        '${s.totalVehicles}',
                        Icons.directions_car_outlined,
                        AppColors.secondary,
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      _statCard(
                        'Rides This Month',
                        '${s.ridesThisMonth}',
                        Icons.route_outlined,
                        AppColors.success,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    _EmployeesTab(),
                    _VehiclesTab(),
                    _OrgSettingsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: AppTypography.h2),
                    Text(
                      label,
                      style: AppTypography.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeesTab extends ConsumerWidget {
  const _EmployeesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeesAsync = ref.watch(adminEmployeesProvider);

    return employeesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Failed to load employees.')),
      data: (employees) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Card(
          child: SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: AppTypography.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                columns: const [
                  DataColumn(label: Text('NAME')),
                  DataColumn(label: Text('EMAIL')),
                  DataColumn(label: Text('DEPARTMENT')),
                  DataColumn(label: Text('ROLE')),
                  DataColumn(label: Text('ACCESS')),
                ],
                rows: employees.map((e) {
                  final granted = e.platformAccess == 'granted';
                  return DataRow(
                    cells: [
                      DataCell(Text(e.name, style: AppTypography.labelLarge)),
                      DataCell(Text(e.email, style: AppTypography.bodySmall)),
                      DataCell(
                        Text(
                          e.department ?? '—',
                          style: AppTypography.bodySmall,
                        ),
                      ),
                      DataCell(
                        _chip(
                          e.role.toUpperCase(),
                          e.role == 'admin'
                              ? AppColors.secondary
                              : AppColors.textSecondary,
                        ),
                      ),
                      DataCell(
                        Row(
                          children: [
                            Switch(
                              value: granted,
                              activeThumbColor: AppColors.success,
                              onChanged: (_) async {
                                final error = await ref
                                    .read(adminActionProvider.notifier)
                                    .toggleEmployeeAccess(
                                      e.id,
                                      e.platformAccess,
                                    );
                                if (error != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(error),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              },
                            ),
                            Text(
                              granted ? 'Granted' : 'Revoked',
                              style: AppTypography.caption.copyWith(
                                color: granted
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VehiclesTab extends ConsumerWidget {
  const _VehiclesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(adminVehiclesProvider);

    return vehiclesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Failed to load vehicles.')),
      data: (vehicles) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Card(
          child: SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: AppTypography.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                columns: const [
                  DataColumn(label: Text('MODEL')),
                  DataColumn(label: Text('REGISTRATION')),
                  DataColumn(label: Text('OWNER')),
                  DataColumn(label: Text('SEATS')),
                  DataColumn(label: Text('STATUS')),
                ],
                rows: vehicles.map((v) {
                  final active = v.status == 'active';
                  return DataRow(
                    cells: [
                      DataCell(Text(v.model, style: AppTypography.labelLarge)),
                      DataCell(
                        Text(
                          v.registrationNumber,
                          style: AppTypography.bodySmall,
                        ),
                      ),
                      DataCell(
                        Text(v.ownerName, style: AppTypography.bodySmall),
                      ),
                      DataCell(
                        Text(
                          '${v.seatingCapacity}',
                          style: AppTypography.bodySmall,
                        ),
                      ),
                      DataCell(
                        Row(
                          children: [
                            Switch(
                              value: active,
                              activeThumbColor: AppColors.success,
                              onChanged: (_) async {
                                final error = await ref
                                    .read(adminActionProvider.notifier)
                                    .toggleVehicleStatus(v.id, v.status);
                                if (error != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(error),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              },
                            ),
                            Text(
                              active ? 'Active' : 'Inactive',
                              style: AppTypography.caption.copyWith(
                                color: active
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrgSettingsTab extends ConsumerStatefulWidget {
  const _OrgSettingsTab();

  @override
  ConsumerState<_OrgSettingsTab> createState() => _OrgSettingsTabState();
}

class _OrgSettingsTabState extends ConsumerState<_OrgSettingsTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _industryController = TextEditingController();
  final _addressController = TextEditingController();
  final _fuelController = TextEditingController();
  final _costKmController = TextEditingController();
  final _travelKmController = TextEditingController();
  String? _orgId;
  bool _populated = false;

  @override
  void dispose() {
    _nameController.dispose();
    _industryController.dispose();
    _addressController.dispose();
    _fuelController.dispose();
    _costKmController.dispose();
    _travelKmController.dispose();
    super.dispose();
  }

  void _populate(OrgSettings? org) {
    if (_populated) return;
    _populated = true;
    _orgId = org?.id;
    _nameController.text = org?.name ?? '';
    _industryController.text = org?.industry ?? '';
    _addressController.text = org?.address ?? '';
    _fuelController.text = (org?.fuelCostPerLiter ?? 100).toStringAsFixed(1);
    _costKmController.text = (org?.costPerKm ?? 12).toStringAsFixed(1);
    _travelKmController.text = (org?.travelCostPerKm ?? 15).toStringAsFixed(1);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final error = await ref
        .read(adminActionProvider.notifier)
        .saveOrgSettings(
          OrgSettings(
            id: _orgId,
            name: _nameController.text.trim(),
            industry: _industryController.text.trim(),
            address: _addressController.text.trim(),
            fuelCostPerLiter: double.tryParse(_fuelController.text) ?? 100,
            costPerKm: double.tryParse(_costKmController.text) ?? 12,
            travelCostPerKm: double.tryParse(_travelKmController.text) ?? 15,
          ),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Organization settings saved.'),
        backgroundColor: error == null ? AppColors.success : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(orgSettingsProvider);
    final isBusy = ref.watch(adminActionProvider);

    return orgAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Failed to load settings.')),
      data: (org) {
        _populate(org);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Organization Settings', style: AppTypography.h4),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Organization Name',
                            ),
                            validator: (v) =>
                                (v?.trim().isEmpty ?? true) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: TextFormField(
                            controller: _industryController,
                            decoration: const InputDecoration(
                              labelText: 'Industry',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'Address'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _fuelController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Fuel Cost / Liter (₹)',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: TextFormField(
                            controller: _costKmController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Cost / km (₹)',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: TextFormField(
                            controller: _travelKmController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Travel Cost / km (₹)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: isBusy ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save Settings'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
