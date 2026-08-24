import 'package:supabase_flutter/supabase_flutter.dart';

class ProviderOrder {
  const ProviderOrder({
    required this.internalOrderId,
    required this.providerOrderId,
    required this.keyId,
    required this.amountPaise,
    required this.currency,
    required this.merchantName,
  });

  final String internalOrderId;
  final String providerOrderId;
  final String keyId;
  final int amountPaise;
  final String currency;
  final String merchantName;
}

class PaymentRepository {
  PaymentRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<ProviderOrder> createProviderOrder(String internalOrderId) async {
    final response = await _client.functions.invoke(
      'create-razorpay-order',
      body: {'order_id': internalOrderId},
    );
    if (response.status != 200 || response.data is! Map) {
      throw const PaymentException('Unable to start secure payment.');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    return ProviderOrder(
      internalOrderId: internalOrderId,
      providerOrderId: data['razorpay_order_id'] as String,
      keyId: data['key_id'] as String,
      amountPaise: data['amount'] as int,
      currency: data['currency'] as String? ?? 'INR',
      merchantName: data['merchant_name'] as String? ?? 'Koyas Fresh Market',
    );
  }

  Future<void> verifyPayment({
    required String internalOrderId,
    required String providerOrderId,
    required String paymentId,
    required String signature,
  }) async {
    final response = await _client.functions.invoke(
      'verify-razorpay-payment',
      body: {
        'order_id': internalOrderId,
        'razorpay_order_id': providerOrderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      },
    );
    if (response.status != 200) {
      throw const PaymentException('Payment verification failed.');
    }
  }
}

class PaymentException implements Exception {
  const PaymentException(this.message);

  final String message;

  @override
  String toString() => message;
}
