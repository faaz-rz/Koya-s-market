import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../orders/models/order.dart';
import 'order_bill.dart';

void printOrderBill(CustomerOrder order) {
  // Keep opening synchronous with the user's click to allow the print tab.
  final receipt = web.window.open('', '_blank');
  if (receipt == null) {
    throw StateError(
      'Allow pop-ups for the staff website, then select Print bill again.',
    );
  }
  try {
    receipt.opener = null;
    final document = receipt.document;
    document.open();
    document.write(buildOrderBillHtml(order).toJS);
    document.close();
    document
        .getElementById('print-bill')!
        .addEventListener('click', ((web.Event _) => receipt.print()).toJS);
    document
        .getElementById('close-bill')!
        .addEventListener('click', ((web.Event _) => receipt.close()).toJS);
    receipt.focus();
    receipt.print();
  } catch (_) {
    receipt.close();
    rethrow;
  }
}
