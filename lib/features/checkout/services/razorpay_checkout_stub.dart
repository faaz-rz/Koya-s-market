import '../data/payment_repository.dart';

class RazorpayCheckout {
  Future<void> open({
    required ProviderOrder order,
    required String customerEmail,
    required String customerPhone,
  }) => throw const PaymentException(
    'Razorpay Checkout is available in the Android and iOS apps.',
  );

  void dispose() {}
}
