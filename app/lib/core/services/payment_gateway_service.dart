import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../constants/app_constants.dart';

/// Result of a gateway checkout.
class GatewayResult {
  final bool success;
  final String? transactionId;
  final String? errorMessage;

  const GatewayResult({
    required this.success,
    this.transactionId,
    this.errorMessage,
  });
}

/// Payment gateway wrapper.
/// - Android/iOS: real Razorpay SDK in test mode.
/// - Web: simulated test-mode checkout (razorpay_flutter has no web support).
class PaymentGatewayService {
  /// Opens a checkout for [amount] rupees. Completes with the result.
  Future<GatewayResult> checkout({
    required double amount,
    required String description,
    String? userEmail,
    String? userPhone,
  }) async {
    if (kIsWeb) {
      // Simulated sandbox checkout on web.
      await Future.delayed(const Duration(seconds: 2));
      final id = 'pay_test_${Random().nextInt(0xFFFFFF).toRadixString(16)}';
      return GatewayResult(success: true, transactionId: id);
    }
    return _razorpayCheckout(
      amount: amount,
      description: description,
      userEmail: userEmail,
      userPhone: userPhone,
    );
  }

  Future<GatewayResult> _razorpayCheckout({
    required double amount,
    required String description,
    String? userEmail,
    String? userPhone,
  }) {
    final completer = Completer<GatewayResult>();
    final razorpay = Razorpay();

    void cleanup() => razorpay.clear();

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS,
        (PaymentSuccessResponse response) {
      cleanup();
      completer.complete(
          GatewayResult(success: true, transactionId: response.paymentId));
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR,
        (PaymentFailureResponse response) {
      cleanup();
      completer.complete(GatewayResult(
        success: false,
        errorMessage: response.message ?? 'Payment failed',
      ));
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {
      cleanup();
      completer.complete(const GatewayResult(
          success: false, errorMessage: 'External wallet not supported'));
    });

    razorpay.open({
      'key': AppConstants.razorpayKeyId,
      'amount': (amount * 100).round(), // paise
      'name': AppConstants.appName,
      'description': description,
      'prefill': {
        'email': ?userEmail,
        'contact': ?userPhone,
      },
    });

    return completer.future;
  }
}
