import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../payment/presentation/providers/payment_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final Widget child;
  const DashboardScreen({super.key, required this.child});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;

  static const _tabs = [
    RouteNames.dashboard,
    RouteNames.myTrips,
    RouteNames.rideHistory,
    RouteNames.myVehicle,
    RouteNames.settings,
  ];

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    context.go(_tabs[index]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync tab index with current route
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _tabs.indexOf(location);
    if (idx != -1 && idx != _currentIndex) {
      setState(() => _currentIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final userName = authState.user?.name ?? 'User';

    return Scaffold(
      appBar: _buildAppBar(userName),
      body: widget.child,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar(String userName) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          // Logo
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.directions_car_rounded,
              color: AppColors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Carpooling',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Wallet
        IconButton(
          onPressed: () => context.push(RouteNames.wallet),
          icon: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  ref.watch(walletProvider).valueOrNull != null
                      ? '₹ ${ref.watch(walletProvider).value!.balance.toStringAsFixed(0)}'
                      : 'Wallet',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Profile
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: GestureDetector(
            onTap: _showProfileMenu,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryLight.withValues(alpha: 0.2),
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }

  void _showProfileMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final user = ref.read(authNotifierProvider).user;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.primaryLight.withValues(
                    alpha: 0.2,
                  ),
                  child: Text(
                    user?.name.isNotEmpty == true
                        ? user!.name[0].toUpperCase()
                        : 'U',
                    style: AppTypography.h2.copyWith(color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(user?.name ?? 'User', style: AppTypography.h4),
                const SizedBox(height: 4),
                Text(user?.email ?? '', style: AppTypography.bodySmall),
                const SizedBox(height: AppSpacing.xxl),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.error),
                  title: Text(
                    'Logout',
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.read(authNotifierProvider.notifier).signOut();
                    if (mounted) {
                      context.go(RouteNames.login);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                0,
                Icons.dashboard_outlined,
                Icons.dashboard_rounded,
                'Dashboard',
              ),
              _buildNavItem(
                1,
                Icons.route_outlined,
                Icons.route_rounded,
                'My Trips',
              ),
              _buildNavItem(
                2,
                Icons.history_outlined,
                Icons.history_rounded,
                'History',
              ),
              _buildNavItem(
                3,
                Icons.directions_car_outlined,
                Icons.directions_car_rounded,
                'Vehicle',
              ),
              _buildNavItem(
                4,
                Icons.settings_outlined,
                Icons.settings_rounded,
                'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final isActive = _currentIndex == index;
    return InkWell(
      onTap: () => _onTabTapped(index),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: isActive
            ? BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppColors.primary : AppColors.textTertiary,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
