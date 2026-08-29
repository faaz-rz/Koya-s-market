import '../data/payment_repository.dart';

class RazorpayCheckout {
  Future<void> open({
    required ProviderOrder order,
    required String customerEmail,
    required String customerPhone,
  }) => throw const PaymentException(
    'Online payment is not included in this release.',
  );

  void dispose() {}
}
