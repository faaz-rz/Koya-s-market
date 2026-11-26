@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/admin/printing/order_bill_printer_web.dart';
import 'package:web/web.dart' as web;

import '../order_bill_test.dart' show billOrder;

void main() {
  test('bill opens the browser print dialog and fits a narrow receipt', () {
    final frame = web.HTMLIFrameElement()
      ..style.cssText =
          'position: fixed; left: -1000px; width: 58mm; border: 0';
    web.document.body!.appendChild(frame);
    addTearDown(frame.remove);

    final JSObject browserWindow = web.window;
    final JSObject receiptWindow = frame.contentWindow!;
    final originalOpen = browserWindow['open'];
    browserWindow['open'] =
        ((JSString url, JSString target) => receiptWindow).toJS;
    addTearDown(() => browserWindow['open'] = originalOpen);

    var printCalls = 0;
    receiptWindow['print'] = (() {
      printCalls++;
    }).toJS;
    printOrderBill(billOrder(itemName: 'Long grain rice, family pack'));
    expect(printCalls, 1);

    final document = frame.contentDocument!;
    expect(document.title, 'Koya Stores - Bill KOY12345');
    final bill = document.querySelector('.bill')!;
    expect(bill.textContent, contains('Long grain rice, family pack'));
    expect(bill.textContent, contains('239.00'));
    expect(bill.clientWidth, closeTo(48 * 96 / 25.4, 1));
    expect(bill.scrollWidth, lessThanOrEqualTo(bill.clientWidth));

    final printButton =
        document.getElementById('print-bill')! as web.HTMLButtonElement;
    printButton.click();
    expect(printCalls, 2);
  });
}
