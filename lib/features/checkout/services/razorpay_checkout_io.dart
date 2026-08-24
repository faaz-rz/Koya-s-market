import 'dart:io';

import '../data/payment_repository.dart';
import 'razorpay_checkout_mobile.dart' as mobile;
import 'razorpay_checkout_stub.dart' as desktop;

/// Routes native checkout to Razorpay only on its supported mobile platforms.
/// Desktop builds retain the full demo checkout without invoking an absent
/// method-channel implementation.
class RazorpayCheckout {
  RazorpayCheckout()
    : _mobile = Platform.isAndroid || Platform.isIOS
          ? mobile.RazorpayCheckout()
          : null,
      _desktop = Platform.isAndroid || Platform.isIOS
          ? null
          : desktop.RazorpayCheckout();

  final mobile.RazorpayCheckout? _mobile;
  final desktop.RazorpayCheckout? _desktop;

  Future<void> open({
    required ProviderOrder order,
    required String customerEmail,
    required String customerPhone,
  }) {
    final mobileCheckout = _mobile;
    if (mobileCheckout != null) {
      return mobileCheckout.open(
        order: order,
        customerEmail: customerEmail,
        customerPhone: customerPhone,
      );
    }
    return _desktop!.open(
      order: order,
      customerEmail: customerEmail,
      customerPhone: customerPhone,
    );
  }

  void dispose() {
    _mobile?.dispose();
    _desktop?.dispose();
  }
}
