import '../../checkout/models/checkout_models.dart';
import '../../orders/models/order.dart';

enum AdminAnalyticsPeriod { daily, monthly, yearly }

class AdminProductAnalytics {
  const AdminProductAnalytics({
    required this.productId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.orderCount,
    required this.salesPaise,
  });

  final String productId;
  final String name;
  final String unit;
  final int quantity;
  final int orderCount;
  final int salesPaise;
}

class AdminSalesAnalytics {
  const AdminSalesAnalytics({
    required this.period,
    required this.orderCount,
    required this.salesPaise,
    required this.productSalesPaise,
    required this.deliveryFeesPaise,
    required this.discountsPaise,
    required this.itemsSold,
    required this.pickupOrders,
    required this.deliveryOrders,
    required this.topProducts,
  });

  final AdminAnalyticsPeriod period;
  final int orderCount;
  final int salesPaise;
  final int productSalesPaise;
  final int deliveryFeesPaise;
  final int discountsPaise;
  final int itemsSold;
  final int pickupOrders;
  final int deliveryOrders;
  final List<AdminProductAnalytics> topProducts;

  int get averageOrderPaise => orderCount == 0 ? 0 : salesPaise ~/ orderCount;
}

abstract final class AdminSalesAnalyticsCalculator {
  static AdminSalesAnalytics calculate({
    required Iterable<CustomerOrder> orders,
    required AdminAnalyticsPeriod period,
    required DateTime now,
  }) {
    final periodOrders = orders.where((order) {
      final recognizedAt = order.paidAt ?? order.createdAt;
      return !recognizedAt.isAfter(now) &&
          _inPeriod(recognizedAt, now, period) &&
          _countsAsSale(order);
    });
    var orderCount = 0;
    var salesPaise = 0;
    var productSalesPaise = 0;
    var deliveryFeesPaise = 0;
    var discountsPaise = 0;
    var itemsSold = 0;
    var pickupOrders = 0;
    var deliveryOrders = 0;
    final products = <String, _MutableProductAnalytics>{};

    for (final order in periodOrders) {
      orderCount++;
      salesPaise += order.totalPaise;
      productSalesPaise += order.subtotalPaise;
      deliveryFeesPaise += order.deliveryChargePaise;
      discountsPaise += order.discountPaise;
      if (order.fulfilmentType == FulfilmentType.pickup) {
        pickupOrders++;
      } else {
        deliveryOrders++;
      }

      final productsInOrder = <String>{};
      for (final item in order.items) {
        itemsSold += item.quantity;
        final key = item.productId.isEmpty
            ? '${item.name}\u0000${item.unit}'
            : item.productId;
        final metric = products.putIfAbsent(
          key,
          () => _MutableProductAnalytics(
            productId: item.productId,
            name: item.name,
            unit: item.unit,
          ),
        );
        metric.quantity += item.quantity;
        metric.salesPaise += item.totalPaise;
        if (productsInOrder.add(key)) metric.orderCount++;
      }
    }

    final topProducts =
        products.values
            .map((product) => product.freeze())
            .toList(growable: false)
          ..sort((left, right) {
            final quantity = right.quantity.compareTo(left.quantity);
            if (quantity != 0) return quantity;
            final sales = right.salesPaise.compareTo(left.salesPaise);
            if (sales != 0) return sales;
            return left.name.compareTo(right.name);
          });

    return AdminSalesAnalytics(
      period: period,
      orderCount: orderCount,
      salesPaise: salesPaise,
      productSalesPaise: productSalesPaise,
      deliveryFeesPaise: deliveryFeesPaise,
      discountsPaise: discountsPaise,
      itemsSold: itemsSold,
      pickupOrders: pickupOrders,
      deliveryOrders: deliveryOrders,
      topProducts: List.unmodifiable(topProducts),
    );
  }

  static bool _countsAsSale(CustomerOrder order) =>
      order.status != OrderStatus.cancelled &&
      order.status != OrderStatus.rejected &&
      order.paymentStatus == PaymentStatus.paid;

  static bool _inPeriod(
    DateTime value,
    DateTime now,
    AdminAnalyticsPeriod period,
  ) => switch (period) {
    AdminAnalyticsPeriod.daily =>
      value.year == now.year &&
          value.month == now.month &&
          value.day == now.day,
    AdminAnalyticsPeriod.monthly =>
      value.year == now.year && value.month == now.month,
    AdminAnalyticsPeriod.yearly => value.year == now.year,
  };
}

class _MutableProductAnalytics {
  _MutableProductAnalytics({
    required this.productId,
    required this.name,
    required this.unit,
  });

  final String productId;
  final String name;
  final String unit;
  int quantity = 0;
  int orderCount = 0;
  int salesPaise = 0;

  AdminProductAnalytics freeze() => AdminProductAnalytics(
    productId: productId,
    name: name,
    unit: unit,
    quantity: quantity,
    orderCount: orderCount,
    salesPaise: salesPaise,
  );
}
