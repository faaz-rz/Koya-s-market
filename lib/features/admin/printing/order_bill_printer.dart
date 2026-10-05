import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/models/order.dart';
import 'order_bill_printer_stub.dart'
    if (dart.library.js_interop) 'order_bill_printer_web.dart'
    as platform;

final orderBillPrinterProvider = Provider<void Function(CustomerOrder)>((ref) {
  return platform.printOrderBill;
});
