import '../../checkout/models/checkout_models.dart';

enum OfferDiscountType { flat, percentage }

class StoreOffer {
  const StoreOffer({
    required this.id,
    this.revision = 0,
    required this.code,
    required this.title,
    required this.minimumSubtotalPaise,
    required this.active,
    this.description = '',
    this.discountType,
    this.discountValue = 0,
    this.maximumDiscountPaise,
    this.freeProductId,
    this.freeQuantity = 1,
    this.requiredFulfilment,
    this.startsAt,
    this.endsAt,
    this.totalRedemptionLimit,
    this.perCustomerLimit = 1,
  });

  final String id;
  final int revision;
  final String code;
  final String title;
  final String description;
  final int minimumSubtotalPaise;
  final OfferDiscountType? discountType;

  /// Paise for a flat discount and whole percentage points for percentage.
  final int discountValue;
  final int? maximumDiscountPaise;
  final String? freeProductId;
  final int freeQuantity;
  final FulfilmentType? requiredFulfilment;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? totalRedemptionLimit;
  final int perCustomerLimit;
  final bool active;

  bool get hasDiscount => discountType != null && discountValue > 0;
  bool get hasFreeProduct => freeProductId?.isNotEmpty == true;

  bool isLiveAt(DateTime now) =>
      active &&
      (startsAt == null || !startsAt!.isAfter(now)) &&
      (endsAt == null || endsAt!.isAfter(now));

  int discountFor(int subtotalPaise) {
    if (!hasDiscount || subtotalPaise <= 0) return 0;
    var discount = switch (discountType!) {
      OfferDiscountType.flat => discountValue,
      OfferDiscountType.percentage =>
        (subtotalPaise * discountValue / 100).floor(),
    };
    final maximum = maximumDiscountPaise;
    if (maximum != null) discount = discount.clamp(0, maximum);
    return discount.clamp(0, subtotalPaise);
  }

  StoreOffer copyWith({
    int? revision,
    String? id,
    String? code,
    String? title,
    String? description,
    int? minimumSubtotalPaise,
    OfferDiscountType? discountType,
    int? discountValue,
    int? maximumDiscountPaise,
    String? freeProductId,
    int? freeQuantity,
    FulfilmentType? requiredFulfilment,
    DateTime? startsAt,
    DateTime? endsAt,
    int? totalRedemptionLimit,
    int? perCustomerLimit,
    bool? active,
    bool clearDiscount = false,
    bool clearMaximumDiscount = false,
    bool clearFreeProduct = false,
    bool clearRequiredFulfilment = false,
    bool clearStartsAt = false,
    bool clearEndsAt = false,
    bool clearTotalRedemptionLimit = false,
  }) {
    return StoreOffer(
      id: id ?? this.id,
      revision: revision ?? this.revision,
      code: code ?? this.code,
      title: title ?? this.title,
      description: description ?? this.description,
      minimumSubtotalPaise: minimumSubtotalPaise ?? this.minimumSubtotalPaise,
      discountType: clearDiscount ? null : discountType ?? this.discountType,
      discountValue: clearDiscount ? 0 : discountValue ?? this.discountValue,
      maximumDiscountPaise: clearMaximumDiscount
          ? null
          : maximumDiscountPaise ?? this.maximumDiscountPaise,
      freeProductId: clearFreeProduct
          ? null
          : freeProductId ?? this.freeProductId,
      freeQuantity: freeQuantity ?? this.freeQuantity,
      requiredFulfilment: clearRequiredFulfilment
          ? null
          : requiredFulfilment ?? this.requiredFulfilment,
      startsAt: clearStartsAt ? null : startsAt ?? this.startsAt,
      endsAt: clearEndsAt ? null : endsAt ?? this.endsAt,
      totalRedemptionLimit: clearTotalRedemptionLimit
          ? null
          : totalRedemptionLimit ?? this.totalRedemptionLimit,
      perCustomerLimit: perCustomerLimit ?? this.perCustomerLimit,
      active: active ?? this.active,
    );
  }
}
