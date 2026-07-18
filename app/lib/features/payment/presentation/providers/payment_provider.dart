import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/payment_gateway_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/payment_remote_datasource.dart';

final paymentGatewayProvider = Provider<PaymentGatewayService>((ref) {
  return PaymentGatewayService();
});

final paymentRemoteDataSourceProvider =
    Provider<PaymentRemoteDataSource>((ref) {
  return PaymentRemoteDataSource(ref.read(supabaseClientProvider));
});

/// Wallet balance + recent transactions.
final walletProvider = FutureProvider<WalletData>((ref) async {
  return ref.read(paymentRemoteDataSourceProvider).getWallet();
});

/// Handles ride payments across all methods.
class PaymentNotifier extends StateNotifier<bool> {
  final Ref _ref;

  PaymentNotifier(this._ref) : super(false);

  /// Pays for a booking. Returns null on success, error message on failure.
  Future<String?> payForBooking({
    required String bookingId,
    required double amount,
    required String method, // cash | card | upi | wallet
  }) async {
    state = true;
    try {
      final dataSource = _ref.read(paymentRemoteDataSourceProvider);
      switch (method) {
        case 'wallet':
          await dataSource.payWithWallet(bookingId);
        case 'cash':
          await dataSource.recordPayment(
            bookingId: bookingId,
            amount: amount,
            method: 'cash',
          );
        case 'card':
        case 'upi':
          final user = _ref.read(authNotifierProvider).user;
          final result = await _ref.read(paymentGatewayProvider).checkout(
                amount: amount,
                description: 'Ride payment',
                userEmail: user?.email,
                userPhone: user?.phone,
              );
          if (!result.success) {
            return result.errorMessage ?? 'Payment failed.';
          }
          await dataSource.recordPayment(
            bookingId: bookingId,
            amount: amount,
            method: method,
            transactionId: result.transactionId,
          );
        default:
          return 'Unknown payment method.';
      }
      _ref.invalidate(walletProvider);
      return null;
    } catch (e) {
      if (e.toString().contains('INSUFFICIENT_BALANCE')) {
        return 'Insufficient wallet balance. Please recharge first.';
      }
      return 'Payment failed. Please try again.';
    } finally {
      state = false;
    }
  }

  /// Recharges the wallet via the gateway. Returns null on success.
  Future<String?> rechargeWallet({
    required double amount,
    required String method, // card | upi
  }) async {
    state = true;
    try {
      final user = _ref.read(authNotifierProvider).user;
      final result = await _ref.read(paymentGatewayProvider).checkout(
            amount: amount,
            description: 'Wallet recharge',
            userEmail: user?.email,
            userPhone: user?.phone,
          );
      if (!result.success) {
        return result.errorMessage ?? 'Recharge failed.';
      }
      await _ref
          .read(paymentRemoteDataSourceProvider)
          .rechargeWallet(amount, description: 'Wallet recharge ($method)');
      _ref.invalidate(walletProvider);
      return null;
    } catch (_) {
      return 'Recharge failed. Please try again.';
    } finally {
      state = false;
    }
  }
}

final paymentNotifierProvider =
    StateNotifierProvider<PaymentNotifier, bool>((ref) {
  return PaymentNotifier(ref);
});
