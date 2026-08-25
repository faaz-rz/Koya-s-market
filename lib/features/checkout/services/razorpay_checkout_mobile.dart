import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../data/payment_repository.dart';

class RazorpayCheckout {
  final Razorpay _razorpay = Razorpay();
  Completer<PaymentSuccessResponse>? _completer;

  Future<void> open({
    required ProviderOrder order,
    required String customerEmail,
    required String customerPhone,
  }) async {
    if (_completer != null) {
      throw const PaymentException('A payment is already in progress.');
    }
    final completer = Completer<PaymentSuccessResponse>();
    _completer = completer;
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onFailure);
    try {
      _razorpay.open({
        'key': order.keyId,
        'order_id': order.providerOrderId,
        'amount': order.amountPaise,
        'currency': order.currency,
        'name': order.merchantName,
        'description': 'Koya Stores order',
        'prefill': {'email': customerEmail, 'contact': customerPhone},
        'theme': {'color': '#5B741E'},
        'retry': {'enabled': true, 'max_count': 2},
      });
      final result = await completer.future;
      final paymentId = result.paymentId;
      final providerOrderId = result.orderId;
      final signature = result.signature;
      if (paymentId == null || providerOrderId == null || signature == null) {
        throw const PaymentException('Razorpay returned an incomplete result.');
      }
      await PaymentRepository().verifyPayment(
        internalOrderId: order.internalOrderId,
        providerOrderId: providerOrderId,
        paymentId: paymentId,
        signature: signature,
      );
    } finally {
      _razorpay.clear();
      _completer = null;
    }
  }

  void _onSuccess(PaymentSuccessResponse response) {
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete(response);
    }
  }

  void _onFailure(PaymentFailureResponse response) {
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        PaymentException(response.message ?? 'Payment was cancelled.'),
      );
    }
  }

  void dispose() {
    _razorpay.clear();
  }
}
