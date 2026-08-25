import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/admin/analytics/admin_sales_analytics.dart';
import 'package:koyas_supermarket/features/checkout/models/checkout_models.dart';
import 'package:koyas_supermarket/features/orders/models/order.dart';

void main() {
  test('admin order history is paged beyond the backend row limit', () {
    final repository = File(
      'lib/features/store/data/supabase_store_repository.dart',
    ).readAsStringSync();

    expect(
      repository,
      contains('Future<List<Map<String, dynamic>>> _loadOrderRows'),
    );
    expect(repository, contains('const pageSize = 500'));
    expect(repository, contains('.range(offset, offset + pageSize - 1)'));
  });

  test('daily, monthly, and yearly sales metrics use valid orders only', () {
    final now = DateTime(2026, 8, 24, 18);
    final orders = [
      _order(
        id: 'today',
        createdAt: DateTime(2026, 8, 24, 10),
        fulfilmentType: FulfilmentType.delivery,
        deliveryChargePaise: 500,
        discountPaise: 300,
        items: const [
          OrderItemSnapshot(
            productId: 'atta',
            name: 'Atta',
            unit: '1 kg',
            unitPricePaise: 1000,
            quantity: 3,
            visualKey: 'grocery',
          ),
          OrderItemSnapshot(
            productId: 'rice',
            name: 'Rice',
            unit: '1 kg',
            unitPricePaise: 2000,
            quantity: 1,
            visualKey: 'grocery',
          ),
        ],
      ),
      _order(
        id: 'month',
        createdAt: DateTime(2026, 8, 3, 12),
        fulfilmentType: FulfilmentType.pickup,
        items: const [
          OrderItemSnapshot(
            productId: 'atta',
            name: 'Atta',
            unit: '1 kg',
            unitPricePaise: 1000,
            quantity: 2,
            visualKey: 'grocery',
          ),
        ],
      ),
      _order(
        id: 'year',
        createdAt: DateTime(2026, 1, 10, 9),
        fulfilmentType: FulfilmentType.pickup,
        items: const [
          OrderItemSnapshot(
            productId: 'tea',
            name: 'Tea',
            unit: '250 g',
            unitPricePaise: 500,
            quantity: 5,
            visualKey: 'grocery',
          ),
        ],
      ),
      _order(
        id: 'cancelled',
        createdAt: DateTime(2026, 8, 24, 11),
        status: OrderStatus.cancelled,
        items: const [
          OrderItemSnapshot(
            productId: 'atta',
            name: 'Atta',
            unit: '1 kg',
            unitPricePaise: 1000,
            quantity: 99,
            visualKey: 'grocery',
          ),
        ],
      ),
      _order(
        id: 'failed',
        createdAt: DateTime(2026, 8, 24, 13),
        paymentStatus: PaymentStatus.failed,
        items: const [
          OrderItemSnapshot(
            productId: 'tea',
            name: 'Tea',
            unit: '250 g',
            unitPricePaise: 500,
            quantity: 20,
            visualKey: 'grocery',
          ),
        ],
      ),
      _order(
        id: 'previous-year',
        createdAt: DateTime(2025, 12, 31, 12),
        items: const [
          OrderItemSnapshot(
            productId: 'rice',
            name: 'Rice',
            unit: '1 kg',
            unitPricePaise: 2000,
            quantity: 10,
            visualKey: 'grocery',
          ),
        ],
      ),
    ];

    final daily = AdminSalesAnalyticsCalculator.calculate(
      orders: orders,
      period: AdminAnalyticsPeriod.daily,
      now: now,
    );
    expect(daily.orderCount, 1);
    expect(daily.salesPaise, 5500);
    expect(daily.productSalesPaise, 5000);
    expect(daily.deliveryFeesPaise, 500);
    expect(daily.discountsPaise, 300);
    expect(daily.itemsSold, 4);
    expect(daily.averageOrderPaise, 5500);
    expect(daily.deliveryOrders, 1);
    expect(daily.pickupOrders, 0);

    final monthly = AdminSalesAnalyticsCalculator.calculate(
      orders: orders,
      period: AdminAnalyticsPeriod.monthly,
      now: now,
    );
    expect(monthly.orderCount, 2);
    expect(monthly.salesPaise, 7500);
    expect(monthly.itemsSold, 6);
    expect(monthly.averageOrderPaise, 3750);
    expect(monthly.pickupOrders, 1);
    expect(monthly.deliveryOrders, 1);

    final yearly = AdminSalesAnalyticsCalculator.calculate(
      orders: orders,
      period: AdminAnalyticsPeriod.yearly,
      now: now,
    );
    expect(yearly.orderCount, 3);
    expect(yearly.salesPaise, 10000);
    expect(yearly.itemsSold, 11);
  });

  test('most ordered products rank by quantity, then sales value', () {
    final analytics = AdminSalesAnalyticsCalculator.calculate(
      orders: [
        _order(
          id: 'one',
          createdAt: DateTime(2026, 8, 24, 10),
          items: const [
            OrderItemSnapshot(
              productId: 'a',
              name: 'Product A',
              unit: '1 pc',
              unitPricePaise: 1000,
              quantity: 2,
              visualKey: 'grocery',
            ),
            OrderItemSnapshot(
              productId: 'b',
              name: 'Product B',
              unit: '1 pc',
              unitPricePaise: 1500,
              quantity: 2,
              visualKey: 'grocery',
            ),
          ],
        ),
        _order(
          id: 'two',
          createdAt: DateTime(2026, 8, 24, 11),
          items: const [
            OrderItemSnapshot(
              productId: 'a',
              name: 'Product A',
              unit: '1 pc',
              unitPricePaise: 1000,
              quantity: 1,
              visualKey: 'grocery',
            ),
            OrderItemSnapshot(
              productId: 'b',
              name: 'Product B',
              unit: '1 pc',
              unitPricePaise: 1500,
              quantity: 1,
              visualKey: 'grocery',
            ),
          ],
        ),
      ],
      period: AdminAnalyticsPeriod.daily,
      now: DateTime(2026, 8, 24, 18),
    );

    expect(analytics.topProducts.map((item) => item.productId), ['b', 'a']);
    expect(analytics.topProducts.first.quantity, 3);
    expect(analytics.topProducts.first.orderCount, 2);
    expect(analytics.topProducts.first.salesPaise, 4500);
  });
}

CustomerOrder _order({
  required String id,
  required DateTime createdAt,
  required List<OrderItemSnapshot> items,
  FulfilmentType fulfilmentType = FulfilmentType.pickup,
  OrderStatus status = OrderStatus.delivered,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  int deliveryChargePaise = 0,
  int discountPaise = 0,
}) {
  final subtotal = items.fold<int>(0, (total, item) => total + item.totalPaise);
  return CustomerOrder(
    id: id,
    items: items,
    fulfilmentType: fulfilmentType,
    fulfilmentDate: createdAt,
    slotLabel: 'Store hours',
    subtotalPaise: subtotal,
    deliveryChargePaise: deliveryChargePaise,
    discountPaise: discountPaise,
    totalPaise: subtotal + deliveryChargePaise,
    paymentMethod: fulfilmentType == FulfilmentType.pickup
        ? PaymentMethod.payAtStore
        : PaymentMethod.cashOnDelivery,
    paymentStatus: paymentStatus,
    status: status,
    createdAt: createdAt,
  );
}
