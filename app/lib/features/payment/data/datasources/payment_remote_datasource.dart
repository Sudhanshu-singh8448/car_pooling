import 'package:supabase_flutter/supabase_flutter.dart';

class WalletTransaction {
  final String id;
  final String type; // credit | debit
  final double amount;
  final double balanceAfter;
  final String? description;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.description,
    required this.createdAt,
  });

  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      id: map['id'] as String,
      type: map['type'] as String,
      amount: (map['amount'] as num).toDouble(),
      balanceAfter: (map['balance_after'] as num).toDouble(),
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }
}

class WalletData {
  final double balance;
  final List<WalletTransaction> transactions;
  const WalletData({required this.balance, required this.transactions});
}

class PaymentRemoteDataSource {
  final SupabaseClient _client;

  PaymentRemoteDataSource(this._client);

  String get _userId => _client.auth.currentUser!.id;

  Future<WalletData> getWallet() async {
    final wallet = await _client
        .from('wallets')
        .select('id, balance')
        .eq('user_id', _userId)
        .maybeSingle();
    if (wallet == null) {
      return const WalletData(balance: 0, transactions: []);
    }
    final txns = await _client
        .from('wallet_transactions')
        .select()
        .eq('wallet_id', wallet['id'] as String)
        .order('created_at', ascending: false)
        .limit(30);
    return WalletData(
      balance: (wallet['balance'] as num).toDouble(),
      transactions: (txns as List)
          .map(
            (t) =>
                WalletTransaction.fromMap(Map<String, dynamic>.from(t as Map)),
          )
          .toList(),
    );
  }

  /// Credit the wallet (called after gateway success).
  Future<double> rechargeWallet(double amount, {String? description}) async {
    final data = await _client.rpc(
      'recharge_wallet',
      params: {
        'p_amount': amount,
        'p_description': description ?? 'Wallet recharge',
      },
    );
    return ((data as Map)['balance'] as num).toDouble();
  }

  /// Pay a booking fare from the wallet (atomic RPC).
  Future<void> payWithWallet(String bookingId) async {
    await _client.rpc('pay_with_wallet', params: {'p_booking_id': bookingId});
  }

  /// Record a completed payment for cash / card / UPI and close the booking.
  Future<void> recordPayment({
    required String bookingId,
    required double amount,
    required String method, // cash | card | upi
    String? transactionId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('payments').insert({
      'booking_id': bookingId,
      'payer_id': _userId,
      'amount': amount,
      'method': method,
      'status': 'completed',
      'transaction_id': transactionId,
      'paid_at': now,
    });
    await _client
        .from('bookings')
        .update({'status': 'payment_completed', 'updated_at': now})
        .eq('id', bookingId);
  }
}
