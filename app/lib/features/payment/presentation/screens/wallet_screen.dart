import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/datasources/payment_remote_datasource.dart';
import '../providers/payment_provider.dart';

/// Screen 11 — wallet balance, recharge, transaction history.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  Future<void> _showRechargeSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _RechargeSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(walletProvider),
        child: walletAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: const [
              SizedBox(height: 120),
              Center(child: Text('Failed to load wallet. Pull to retry.')),
            ],
          ),
          data: (wallet) => ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available Balance',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '₹ ${wallet.balance.toStringAsFixed(2)}',
                      style: AppTypography.h1.copyWith(color: AppColors.white),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ElevatedButton.icon(
                      onPressed: () => _showRechargeSheet(context, ref),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.white,
                        foregroundColor: AppColors.primary,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Recharge Wallet'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text('Recent Transactions', style: AppTypography.h4),
              const SizedBox(height: AppSpacing.md),
              if (wallet.transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.huge,
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'No transactions yet',
                          style: AppTypography.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...wallet.transactions.map((t) => _TransactionTile(txn: t)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final WalletTransaction txn;
  const _TransactionTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isCredit = txn.type == 'credit';
    final color = isCredit ? AppColors.success : AppColors.error;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(
            isCredit ? Icons.south_west : Icons.north_east,
            size: 18,
            color: color,
          ),
        ),
        title: Text(
          txn.description ?? (isCredit ? 'Credit' : 'Debit'),
          style: AppTypography.labelLarge,
        ),
        subtitle: Text(
          timeago.format(txn.createdAt),
          style: AppTypography.caption,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isCredit ? '+' : '-'} ₹ ${txn.amount.toStringAsFixed(0)}',
              style: AppTypography.labelLarge.copyWith(color: color),
            ),
            Text(
              'Bal: ₹ ${txn.balanceAfter.toStringAsFixed(0)}',
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _RechargeSheet extends ConsumerStatefulWidget {
  const _RechargeSheet();

  @override
  ConsumerState<_RechargeSheet> createState() => _RechargeSheetState();
}

class _RechargeSheetState extends ConsumerState<_RechargeSheet> {
  final _amountController = TextEditingController(text: '500');
  String _method = 'upi';
  static const _presets = [100.0, 200.0, 500.0, 1000.0];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _recharge() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid amount.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final error = await ref
        .read(paymentNotifierProvider.notifier)
        .rechargeWallet(amount: amount, method: _method);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('₹ ${amount.toStringAsFixed(0)} added to wallet!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = ref.watch(paymentNotifierProvider);
    final gatewayNote = kIsWeb
        ? 'via Razorpay (Test Mode — simulated)'
        : 'via Razorpay (Test Mode)';

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenPadding,
        right: AppSpacing.screenPadding,
        top: AppSpacing.xl,
        bottom:
            MediaQuery.of(context).viewInsets.bottom + AppSpacing.screenPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Recharge Wallet', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.xs),
          Text(gatewayNote, style: AppTypography.caption),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount (₹)',
              prefixIcon: Icon(Icons.currency_rupee),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: _presets
                .map(
                  (p) => ActionChip(
                    label: Text('₹ ${p.toStringAsFixed(0)}'),
                    onPressed: () =>
                        _amountController.text = p.toStringAsFixed(0),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'upi',
                label: Text('UPI'),
                icon: Icon(Icons.qr_code_2),
              ),
              ButtonSegment(
                value: 'card',
                label: Text('Card'),
                icon: Icon(Icons.credit_card),
              ),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isBusy ? null : _recharge,
              child: isBusy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Text('Proceed to Recharge'),
            ),
          ),
        ],
      ),
    );
  }
}
