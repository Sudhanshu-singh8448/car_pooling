import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Screen 14 — settings and navigation hub.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).user;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          // Profile header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.1),
                    child: Text(
                      (user?.name.isNotEmpty ?? false)
                          ? user!.name[0].toUpperCase()
                          : '?',
                      style: AppTypography.h3
                          .copyWith(color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.name ?? 'User',
                            style: AppTypography.h4),
                        Text(user?.email ?? '',
                            style: AppTypography.bodySmall),
                        if (user?.isAdmin ?? false)
                          Container(
                            margin:
                                const EdgeInsets.only(top: AppSpacing.xs),
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.secondary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusFull),
                            ),
                            child: Text(
                              'ADMIN',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle('Account'),
          _tile(context, Icons.account_balance_wallet_outlined, 'Wallet',
              () => context.push(RouteNames.wallet)),
          _tile(context, Icons.directions_car_outlined, 'My Vehicles',
              () => context.go(RouteNames.myVehicle)),
          _tile(context, Icons.route_outlined, 'My Trips',
              () => context.go(RouteNames.myTrips)),
          _tile(context, Icons.history, 'Ride History',
              () => context.go(RouteNames.rideHistory)),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle('Insights'),
          _tile(context, Icons.insert_chart_outlined, 'Reports',
              () => context.push(RouteNames.reports)),
          if (user?.isAdmin ?? false)
            _tile(context, Icons.admin_panel_settings_outlined,
                'Admin Dashboard',
                () => context.push(RouteNames.adminDashboard)),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle('Other'),
          _tile(context, Icons.help_outline, 'Help & Support', () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Contact support@carpooling.demo')));
          }),
          _tile(
            context,
            Icons.logout,
            'Logout',
            () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                        onPressed: () => dialogContext.pop(false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => dialogContext.pop(true),
                        child: const Text('Logout',
                            style: TextStyle(color: AppColors.error))),
                  ],
                ),
              );
              if (confirmed ?? false) {
                await ref.read(authNotifierProvider.notifier).signOut();
              }
            },
            color: AppColors.error,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(
          left: AppSpacing.xs, bottom: AppSpacing.sm),
      child: Text(title,
          style: AppTypography.labelMedium
              .copyWith(color: AppColors.textTertiary)),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title,
      VoidCallback onTap,
      {Color? color}) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(icon, color: color ?? AppColors.textSecondary),
        title: Text(title,
            style: AppTypography.labelLarge
                .copyWith(color: color ?? AppColors.textPrimary)),
        trailing: const Icon(Icons.chevron_right,
            color: AppColors.textTertiary, size: 20),
        onTap: onTap,
      ),
    );
  }
}
