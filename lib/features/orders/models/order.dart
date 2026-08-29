import '../../checkout/models/checkout_models.dart';

enum PaymentStatus { pending, paid, failed, cancelled }

enum OrderStatus {
  placed,
  confirmed,
  preparing,
  readyForPickup,
  collected,
  readyForDispatch,
  outForDelivery,
  delivered,
  cancelled,
  rejected,
}

class OrderItemSnapshot {
  const OrderItemSnapshot({
    required this.productId,
    required this.name,
    required this.unit,
    required this.unitPricePaise,
    required this.quantity,
    required this.visualKey,
    this.isFreeOfferItem = false,
  });

  final String productId;
  final String name;
  final String unit;
  final int unitPricePaise;
  final int quantity;
  final String visualKey;
  final bool isFreeOfferItem;

  int get totalPaise => unitPricePaise * quantity;
}

class CustomerOrder {
  const CustomerOrder({
    required this.id,
    required this.items,
    required this.fulfilmentType,
    required this.fulfilmentDate,
    required this.slotLabel,
    required this.subtotalPaise,
    required this.deliveryChargePaise,
    required this.discountPaise,
    required this.totalPaise,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.status,
    required this.createdAt,
    this.reference,
    this.addressText,
    this.deliveryInstructions = '',
    this.customerName = '',
    this.customerPhone = '',
    this.deliveryRecipientName = '',
    this.deliveryRecipientPhone = '',
    this.paidAt,
    this.offerCode,
    this.offerTitle,
    this.offerDiscountPaise = 0,
  });

  final String id;
  final List<OrderItemSnapshot> items;
  final FulfilmentType fulfilmentType;
  final DateTime fulfilmentDate;
  final String slotLabel;
  final String? addressText;
  final int subtotalPaise;
  final int deliveryChargePaise;
  final int discountPaise;
  final int totalPaise;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final OrderStatus status;
  final String deliveryInstructions;
  final String customerName;
  final String customerPhone;
  final String deliveryRecipientName;
  final String deliveryRecipientPhone;
  final DateTime createdAt;
  final DateTime? paidAt;
  final String? offerCode;
  final String? offerTitle;
  final int offerDiscountPaise;
  final String? reference;

  String get displayReference => reference ?? id;

  CustomerOrder copyWith({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    DateTime? paidAt,
  }) {
    return CustomerOrder(
      id: id,
      items: items,
      fulfilmentType: fulfilmentType,
      fulfilmentDate: fulfilmentDate,
      slotLabel: slotLabel,
      addressText: addressText,
      subtotalPaise: subtotalPaise,
      deliveryChargePaise: deliveryChargePaise,
      discountPaise: discountPaise,
      totalPaise: totalPaise,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      status: status ?? this.status,
      deliveryInstructions: deliveryInstructions,
      customerName: customerName,
      customerPhone: customerPhone,
      deliveryRecipientName: deliveryRecipientName,
      deliveryRecipientPhone: deliveryRecipientPhone,
      createdAt: createdAt,
      paidAt: paidAt ?? this.paidAt,
      offerCode: offerCode,
      offerTitle: offerTitle,
      offerDiscountPaise: offerDiscountPaise,
      reference: reference,
    );
  }
}
