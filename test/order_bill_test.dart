import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/admin/printing/order_bill.dart';
import 'package:koyas_supermarket/features/checkout/models/checkout_models.dart';
import 'package:koyas_supermarket/features/orders/models/order.dart';

CustomerOrder billOrder({
  FulfilmentType fulfilment = FulfilmentType.delivery,
  String name = 'Sample customer',
  String itemName = 'Rice & grains',
  PaymentStatus payment = PaymentStatus.pending,
  OrderStatus status = OrderStatus.placed,
}) => CustomerOrder(
  id: 'internal-id',
  reference: 'KOY12345',
  items: [
    OrderItemSnapshot(
      productId: 'rice',
      name: itemName,
      unit: '1 kg',
      unitPricePaise: 10025,
      quantity: 2,
      visualKey: 'grocery',
    ),
    const OrderItemSnapshot(
      productId: 'gift',
      name: 'Free gift',
      unit: '1 pack',
      unitPricePaise: 0,
      quantity: 1,
      visualKey: 'grocery',
      isFreeOfferItem: true,
    ),
  ],
  fulfilmentType: fulfilment,
  fulfilmentDate: DateTime(2026, 9, 5),
  slotLabel: '6 PM - 9 PM',
  subtotalPaise: 20050,
  deliveryChargePaise: fulfilment == FulfilmentType.delivery ? 4900 : 0,
  discountPaise: 4050,
  offerDiscountPaise: 1050,
  offerCode: 'SAVE',
  totalPaise: fulfilment == FulfilmentType.delivery ? 23900 : 19000,
  paymentMethod: fulfilment == FulfilmentType.delivery
      ? PaymentMethod.cashOnDelivery
      : PaymentMethod.payAtStore,
  paymentStatus: payment,
  status: status,
  createdAt: DateTime(2026, 9, 4, 14, 35),
  paidAt: payment == PaymentStatus.paid ? DateTime(2026, 9, 4, 16) : null,
  customerName: name,
  customerPhone: '90000 00000',
  deliveryRecipientName: 'Sample recipient',
  deliveryRecipientPhone: '90000 00001',
  addressText: '12 Sample Street',
  deliveryInstructions: 'Call on arrival.',
);

void main() {
  test(
    'bill keeps saved paise, free items, and discounts without double counting',
    () {
      final html = buildOrderBillHtml(billOrder());
      expect(html, contains('Bill no.:</strong> KOY12345'));
      expect(html, isNot(contains('internal-id')));
      expect(html, contains('04&#47;09&#47;2026 2:35 PM'));
      expect(html, contains('>100.25</td>'));
      expect(html, contains('>200.50</td>'));
      expect(html, contains('1 pack · FREE'));
      expect(html, contains('>0.00</td>'));
      expect(html, contains('Offer (SAVE)</th><td>-10.50</td>'));
      expect(html, contains('TOTAL (INR)</th><td>239.00</td>'));
      expect(html, contains('You saved INR 40.50'));
      expect(html, isNot(contains('-40.50')));
      expect(html, contains('Items: 2 | Qty: 3'));
      expect(html, contains('Sample recipient'));
      expect(html, contains('90000 00001'));
      expect(html, contains('12 Sample Street'));
      expect(html, contains('PAYMENT PENDING'));
      expect(html, isNot(contains('Received:</strong>')));
    },
  );

  test('pickup bills omit delivery details and show received payments', () {
    final html = buildOrderBillHtml(
      billOrder(fulfilment: FulfilmentType.pickup, payment: PaymentStatus.paid),
    );
    expect(html, contains('Store pickup'));
    expect(html, contains('Cash or UPI at pickup'));
    expect(html, contains('TOTAL (INR)</th><td>190.00</td>'));
    expect(html, contains('>PAID</p>'));
      expect(html, contains('Received:</strong> 04&#47;09&#47;2026 4:00 PM'));
    expect(html, isNot(contains('Sample recipient')));
    expect(html, isNot(contains('12 Sample Street')));
    expect(html, isNot(contains('Call on arrival.')));
  });

  test(
    'customer and item text cannot inject markup or scripts into a bill',
    () {
      final html = buildOrderBillHtml(
        billOrder(
          name: '<script>alert("customer")</script>',
          itemName: '<img src=x onerror="alert(1)"> & rice',
        ),
      );
      expect(html, contains('&lt;script&gt;'));
      expect(html, contains('&lt;img'));
      expect(html, contains('&amp; rice'));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<img')));
    },
  );

  test('cancelled and rejected orders are clearly identified on the bill', () {
    expect(
      buildOrderBillHtml(billOrder(status: OrderStatus.cancelled)),
      contains('ORDER CANCELLED'),
    );
    expect(
      buildOrderBillHtml(billOrder(status: OrderStatus.rejected)),
      contains('ORDER REJECTED'),
    );
  });
}
