import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../trip/domain/entities/trip_entity.dart';
import '../../../trip/presentation/providers/trip_provider.dart';
import '../providers/payment_provider.dart';

/// Screen 10 — choose how to pay for the completed trip.
class PaymentMethodScreen extends ConsumerStatefulWidget {
  final TripEntity trip;
  const PaymentMethodScreen({super.key, required this.trip});

  @override
  ConsumerState<PaymentMethodScreen> createState() =>
      _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends ConsumerState<PaymentMethodScreen> {
  String _method = 'upi';

  double get _fare => widget.trip.booking?.totalFare ?? 0;

  Future<void> _pay() async {
    final bookingId = widget.trip.booking?.id;
    if (bookingId == null) return;

    final error = await ref.read(paymentNotifierProvider.notifier).payForBooking(
          bookingId: bookingId,
          amount: _fare,
          method: _method,
        );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    ref.invalidate(activeTripsProvider);
    ref.invalidate(pastTripsProvider);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 64, color: AppColors.success),
            const SizedBox(height: AppSpacing.lg),
            Text('Payment Successful!', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '₹ ${_fare.toStringAsFixed(0)} paid via ${_methodLabel(_method)}',
              style: AppTypography.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              dialogContext.pop();
              context.go(RouteNames.rideHistory);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _methodLabel(String method) => switch (method) {
        'wallet' => 'Wallet',
        'cash' => 'Cash',
        'card' => 'Card',
        'upi' => 'UPI',
        _ => method,
      };

  @override
  Widget build(BuildContext context) {
    final isBusy = ref.watch(paymentNotifierProvider);
    final walletAsync = ref.watch(walletProvider);
    final walletBalance = walletAsync.valueOrNull?.balance ?? 0;
    final gatewayNote = kIsWeb ? 'Razorpay (Test Mode — simulated)' : 'Razorpay (Test Mode)';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Payment Method'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Amount to pay', style: AppTypography.labelLarge),
                    Text(
                      '₹ ${_fare.toStringAsFixed(0)}',
                      style:
                          AppTypography.h3.copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Select a payment method', style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.md),
            _option(
              value: 'upi',
              icon: Icons.qr_code_2,
              title: 'UPI',
              subtitle: gatewayNote,
            ),
            _option(
              value: 'card',
              icon: Icons.credit_card,
              title: 'Credit / Debit Card',
              subtitle: gatewayNote,
            ),
            _option(
              value: 'wallet',
              icon: Icons.account_balance_wallet_outlined,
              title: 'Wallet',
              subtitle: 'Balance: ₹ ${walletBalance.toStringAsFixed(0)}',
              enabled: walletBalance >= _fare,
              trailing: walletBalance < _fare
                  ? TextButton(
                      onPressed: () => context.push(RouteNames.wallet),
                      child: const Text('Recharge'),
                    )
                  : null,
            ),
            _option(
              value: 'cash',
              icon: Icons.money,
              title: 'Cash',
              subtitle: 'Pay the driver directly',
            ),
            const SizedBox(height: AppSpacing.xxxl),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: isBusy ? null : _pay,
                child: isBusy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.white),
                      )
                    : Text('Pay ₹ ${_fare.toStringAsFixed(0)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    bool enabled = true,
    Widget? trailing,
  }) {
    final selected = _method == value;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: enabled ? () => setState(() => _method = value) : null,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: enabled
              ? (selected ? AppColors.primary : AppColors.textTertiary)
              : AppColors.border,
        ),
        title: Row(
          children: [
            Icon(icon,
                size: 20,
                color: enabled ? AppColors.primary : AppColors.textTertiary),
            const SizedBox(width: AppSpacing.md),
            Text(title, style: AppTypography.labelLarge),
            if (trailing != null) ...[const Spacer(), trailing],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Text(subtitle, style: AppTypography.caption),
        ),
      ),
    );
  }
}
