import 'dart:convert';

import 'package:intl/intl.dart';

import '../../checkout/models/checkout_models.dart';
import '../../orders/models/order.dart';

/// Uses the order's saved prices, never the current product catalogue.
String buildOrderBillHtml(CustomerOrder order) {
  const escape = HtmlEscape();
  String html(String value) => escape.convert(value);
  final currency = NumberFormat('#,##,##0.00', 'en_IN');
  String money(int paise) => currency.format(paise / 100);
  String field(String label, String value) =>
      '<p><strong>${html(label)}:</strong> ${html(value)}</p>';
  String amount(String label, int paise, {bool total = false}) =>
      '<tr${total ? ' class="grand-total"' : ''}>'
      '<th scope="row">${html(label)}</th><td>${money(paise)}</td></tr>';
  String recorded(String value) =>
      value.trim().isEmpty ? 'Not recorded' : value.trim();

  final delivery = order.fulfilmentType == FulfilmentType.delivery;
  final customer = recorded(order.customerName);
  final phone = recorded(order.customerPhone);
  final recipient = order.deliveryRecipientName.trim().isEmpty
      ? customer
      : order.deliveryRecipientName.trim();
  final recipientPhone = order.deliveryRecipientPhone.trim().isEmpty
      ? phone
      : order.deliveryRecipientPhone.trim();
  final paymentMethod = switch (order.paymentMethod) {
    PaymentMethod.cashOnDelivery => 'Cash or UPI on delivery',
    PaymentMethod.payAtStore => 'Cash or UPI at pickup',
    PaymentMethod.online => 'Online payment',
  };
  final paymentStatus = switch (order.paymentStatus) {
    PaymentStatus.pending => 'PAYMENT PENDING',
    PaymentStatus.paid => 'PAID',
    PaymentStatus.failed => 'PAYMENT FAILED',
    PaymentStatus.cancelled => 'PAYMENT CANCELLED',
  };
  final closedWithoutSale = switch (order.status) {
    OrderStatus.cancelled => 'ORDER CANCELLED',
    OrderStatus.rejected => 'ORDER REJECTED',
    _ => null,
  };
  final offerCode = order.offerCode?.trim() ?? '';
  final rows = order.items.indexed.map((entry) {
    final (index, item) = entry;
    return '<tr>'
        '<td>${index + 1}. ${html(item.name)}'
        '<span class="unit">${html(item.unit)}'
        '${item.isFreeOfferItem ? ' · FREE' : ''}</span></td>'
        '<td class="number">${item.quantity}</td>'
        '<td class="number">${money(item.unitPricePaise)}</td>'
        '<td class="number">${money(item.totalPaise)}</td></tr>';
  }).join();
  // Product discounts are already included in item rates and subtotal.
  // Only the order-level offer is subtracted again below.
  final totals = [
    amount('Subtotal', order.subtotalPaise),
    amount('Delivery', order.deliveryChargePaise),
    if (order.offerDiscountPaise > 0)
      amount(
        offerCode.isEmpty ? 'Offer discount' : 'Offer ($offerCode)',
        -order.offerDiscountPaise,
      ),
    amount('TOTAL (INR)', order.totalPaise, total: true),
  ].join();

  return '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Koya Stores - Bill ${html(order.displayReference)}</title>
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; background: #eee; color: #000;
      font: 12px/1.45 "Courier New", monospace; }
    .toolbar { padding: 16px; text-align: center; font: 14px/1.5 Arial, sans-serif; }
    .toolbar p { margin: 8px 0 0; }
    button { padding: 10px 16px; margin: 0 4px; border: 1px solid #222;
      border-radius: 4px; background: #fff; color: #000; cursor: pointer; }
    button:first-child { background: #111; color: #fff; }
    .bill { width: 80mm; max-width: 100%; padding: 4mm; margin: 0 auto 24px;
      background: #fff; overflow-wrap: anywhere; }
    header { text-align: center; padding-bottom: 10px; }
    h1 { margin: 0 0 4px; font-size: 22px; letter-spacing: 1px; }
    h2 { margin: 12px 0 0; font-size: 14px; letter-spacing: 2px; }
    p { margin: 3px 0; white-space: pre-line; }
    .details { border-top: 1px dashed #000; padding: 8px 0; }
    .status { text-align: center; font-weight: bold; margin: 8px 0; }
    table { width: 100%; border-collapse: collapse; font-size: 11px; }
    thead { display: table-header-group; }
    th { text-align: left; }
    .items thead { border-top: 1px dashed #000; border-bottom: 1px dashed #000; }
    .items th, .items td { padding: 6px 2px; vertical-align: top; }
    .items { table-layout: fixed; }
    .items th:first-child { width: 42%; }
    .items th:nth-child(2) { width: 12%; }
    .items th:nth-child(3), .items th:nth-child(4) { width: 23%; }
    .number { text-align: right; }
    .unit { display: block; font-size: 10px; }
    tr { break-inside: avoid; page-break-inside: avoid; }
    .summary { border-top: 1px dashed #000; padding-top: 8px; break-inside: avoid; }
    .totals { font-size: 12px; }
    .totals th, .totals td { padding: 3px 0; font-weight: normal; }
    .totals td { text-align: right; }
    .grand-total { border-top: 1px solid #000; border-bottom: 3px double #000; }
    .grand-total th, .grand-total td { padding: 8px 0; font-size: 15px; font-weight: bold; }
    .count, .savings { text-align: center; margin: 9px 0; }
    footer { text-align: center; border-top: 1px dashed #000; margin-top: 12px;
      padding-top: 10px; break-inside: avoid; }
    @page { size: auto; margin: 4mm; }
    @media print {
      body { background: #fff; }
      .toolbar { display: none; }
      .bill { width: 72mm; max-width: 100%; padding: 0; margin: 0; }
    }
  </style>
</head>
<body>
  <nav class="toolbar" aria-label="Bill actions">
    <button id="print-bill" type="button">Print / Save PDF</button>
    <button id="close-bill" type="button">Close</button>
    <p>Select your printer's paper size (80 mm receipt or A4).<br>
    For a clean bill, turn off browser headers and footers.</p>
  </nav>
  <main class="bill">
    <header>
      <h1>KOYA STORES</h1>
      <p>9-1, 43/5, Prashanth Nagar, Langar Houz<br>Hyderabad, Telangana 500008</p>
      <p>Phone: +91 95029 26383</p>
      <h2>ORDER BILL</h2>
    </header>
    <section class="details">
      ${field('Bill no.', order.displayReference)}
      ${field('Date', DateFormat('dd/MM/yyyy h:mm a').format(order.createdAt.toLocal()))}
      ${field('Order type', delivery ? 'Home delivery' : 'Store pickup')}
      ${closedWithoutSale == null ? '' : '<p class="status">$closedWithoutSale</p>'}
    </section>
    <section class="details">
      ${field('Customer', customer)}
      ${field('Phone', phone)}
      ${delivery && recipient != customer ? field('Deliver to', recipient) : ''}
      ${delivery && recipientPhone != phone ? field('Recipient phone', recipientPhone) : ''}
      ${delivery ? field('Address', recorded(order.addressText ?? '')) : ''}
      ${delivery ? field('Delivery slot', '${DateFormat('dd/MM/yyyy').format(order.fulfilmentDate)} · ${order.slotLabel}') : ''}
      ${delivery && order.deliveryInstructions.trim().isNotEmpty ? field('Instructions', order.deliveryInstructions.trim()) : ''}
    </section>
    <table class="items" aria-label="Bill items, amounts in INR">
      <thead><tr><th scope="col">Item</th><th scope="col" class="number">Qty</th>
      <th scope="col" class="number">Rate</th><th scope="col" class="number">Amount</th></tr></thead>
      <tbody>$rows</tbody>
    </table>
    <section class="summary">
      <table class="totals" aria-label="Bill totals in INR">$totals</table>
      <p class="count">Items: ${order.items.length} | Qty: ${order.items.fold<int>(0, (sum, item) => sum + item.quantity)}</p>
      ${order.discountPaise > 0 ? '<p class="savings">You saved INR ${money(order.discountPaise)}</p>' : ''}
      ${offerCode.isNotEmpty && order.offerDiscountPaise == 0 ? field('Offer', offerCode) : ''}
      ${field('Payment', paymentMethod)}
      <p class="status">$paymentStatus</p>
      ${order.paidAt == null ? '' : field('Received', DateFormat('dd/MM/yyyy h:mm a').format(order.paidAt!.toLocal()))}
    </section>
    <footer><p>Thank you for shopping with us!</p><p>Please visit again.</p></footer>
  </main>
</body>
</html>''';
}
