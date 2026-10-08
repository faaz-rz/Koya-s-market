import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/utils/transaction_request.dart';
import '../../cart/models/cart_item.dart';
import '../../checkout/models/checkout_models.dart';
import '../../offers/models/store_offer.dart';
import '../../orders/models/order.dart';
import '../../products/models/category.dart';
import '../../products/models/product.dart';
import '../../profile/models/customer_profile.dart';
import '../data/demo_store_data.dart';

class StoreValidationException implements Exception {
  const StoreValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StoreState {
  const StoreState({
    required this.categories,
    required this.products,
    required this.addresses,
    required this.orders,
    this.offers = const [],
    required this.pickupSlots,
    required this.deliverySlots,
    required this.serviceablePincodes,
    this.minimumOrderPaise = 0,
    this.settingsRevision = 0,
    this.baseDeliveryChargePaise = 4900,
    this.freeDeliveryThresholdPaise = 79900,
    this.pickupEnabled = true,
    this.deliveryEnabled = true,
    this.cashOnDeliveryEnabled = true,
    required this.selectedDate,
    this.profile,
    this.isAuthenticated = false,
    this.isAdminView = false,
    this.isAdminAccount = false,
    this.cartQuantities = const {},
    this.favoriteProductIds = const {},
    this.fulfilmentType = FulfilmentType.pickup,
    this.selectedSlotLabel = 'Store hours',
    this.selectedAddressId = 'home-1',
    this.paymentMethod = PaymentMethod.payAtStore,
    this.deliveryInstructions = '',
    this.selectedOfferCode,
    this.lastOrderId,
  });

  final CustomerProfile? profile;
  final bool isAuthenticated;
  final bool isAdminView;
  final bool isAdminAccount;
  final List<ProductCategory> categories;
  final List<Product> products;
  final Map<String, int> cartQuantities;
  final Set<String> favoriteProductIds;
  final List<CustomerAddress> addresses;
  final List<CustomerOrder> orders;
  final List<StoreOffer> offers;
  final List<FulfilmentSlot> pickupSlots;
  final List<FulfilmentSlot> deliverySlots;
  final Set<String> serviceablePincodes;
  final int minimumOrderPaise;
  final int settingsRevision;
  final int baseDeliveryChargePaise;
  final int freeDeliveryThresholdPaise;
  final bool pickupEnabled;
  final bool deliveryEnabled;
  final bool cashOnDeliveryEnabled;
  final FulfilmentType fulfilmentType;
  final DateTime selectedDate;
  final String selectedSlotLabel;
  final String selectedAddressId;
  final PaymentMethod paymentMethod;
  final String deliveryInstructions;
  final String? selectedOfferCode;
  final String? lastOrderId;

  bool get needsAddressSetup =>
      isAuthenticated && !isAdminAccount && addresses.isEmpty;

  Product? productById(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  CustomerAddress? get selectedAddress {
    for (final address in addresses) {
      if (address.id == selectedAddressId) return address;
    }
    return null;
  }

  List<CartItem> get cartItems => cartQuantities.entries
      .map((entry) {
        final product = productById(entry.key);
        return product == null
            ? null
            : CartItem(product: product, quantity: entry.value);
      })
      .whereType<CartItem>()
      .toList(growable: false);

  int get cartCount => cartQuantities.values.fold(0, (a, b) => a + b);
  int get subtotalPaise => cartItems.fold(0, (a, b) => a + b.totalPaise);
  int get savingsPaise => cartItems.fold(
    0,
    (total, item) =>
        total +
        (item.product.pricePaise - item.product.effectivePricePaise) *
            item.quantity,
  );
  int get deliveryChargePaise =>
      fulfilmentType == FulfilmentType.delivery &&
          subtotalPaise < freeDeliveryThresholdPaise
      ? baseDeliveryChargePaise
      : 0;

  StoreOffer? offerByCode(String code) {
    final normalized = code.trim().toUpperCase();
    for (final offer in offers) {
      if (offer.code.toUpperCase() == normalized) return offer;
    }
    return null;
  }

  String? offerIneligibilityReason(StoreOffer offer, {DateTime? now}) {
    final checkTime = now ?? DateTime.now();
    if (!offer.isLiveAt(checkTime)) return 'This offer is not active.';
    if (offer.requiredFulfilment != null &&
        offer.requiredFulfilment != fulfilmentType) {
      return offer.requiredFulfilment == FulfilmentType.pickup
          ? 'This offer is available for pickup orders only.'
          : 'This offer is available for delivery orders only.';
    }
    if (subtotalPaise < offer.minimumSubtotalPaise) {
      final shortfall = offer.minimumSubtotalPaise - subtotalPaise;
      return 'Add ₹${(shortfall / 100).toStringAsFixed(2)} more to use this offer.';
    }
    if (offer.hasFreeProduct) {
      final product = productById(offer.freeProductId!);
      if (product == null || !product.isAvailable) {
        return 'The free product is currently unavailable.';
      }
      final alreadyInCart = cartQuantities[product.id] ?? 0;
      if (product.stockQuantity - alreadyInCart < offer.freeQuantity) {
        return 'There is not enough stock for the free product.';
      }
    }
    return null;
  }

  StoreOffer? get selectedOffer =>
      selectedOfferCode == null ? null : offerByCode(selectedOfferCode!);

  StoreOffer? get appliedOffer {
    final offer = selectedOffer;
    return offer != null && offerIneligibilityReason(offer) == null
        ? offer
        : null;
  }

  int get offerDiscountPaise => appliedOffer?.discountFor(subtotalPaise) ?? 0;

  Product? get freeOfferProduct {
    final productId = appliedOffer?.freeProductId;
    return productId == null ? null : productById(productId);
  }

  int get totalPaise =>
      max(0, subtotalPaise + deliveryChargePaise - offerDiscountPaise);

  StoreState copyWith({
    CustomerProfile? profile,
    bool? isAuthenticated,
    bool? isAdminView,
    bool? isAdminAccount,
    List<ProductCategory>? categories,
    List<Product>? products,
    Map<String, int>? cartQuantities,
    Set<String>? favoriteProductIds,
    List<CustomerAddress>? addresses,
    List<CustomerOrder>? orders,
    List<StoreOffer>? offers,
    List<FulfilmentSlot>? pickupSlots,
    List<FulfilmentSlot>? deliverySlots,
    Set<String>? serviceablePincodes,
    int? minimumOrderPaise,
    int? settingsRevision,
    int? baseDeliveryChargePaise,
    int? freeDeliveryThresholdPaise,
    bool? pickupEnabled,
    bool? deliveryEnabled,
    bool? cashOnDeliveryEnabled,
    FulfilmentType? fulfilmentType,
    DateTime? selectedDate,
    String? selectedSlotLabel,
    String? selectedAddressId,
    PaymentMethod? paymentMethod,
    String? deliveryInstructions,
    String? selectedOfferCode,
    String? lastOrderId,
    bool clearProfile = false,
    bool clearLastOrder = false,
    bool clearSelectedOffer = false,
  }) {
    return StoreState(
      profile: clearProfile ? null : profile ?? this.profile,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isAdminView: isAdminView ?? this.isAdminView,
      isAdminAccount: isAdminAccount ?? this.isAdminAccount,
      categories: categories ?? this.categories,
      products: products ?? this.products,
      cartQuantities: cartQuantities ?? this.cartQuantities,
      favoriteProductIds: favoriteProductIds ?? this.favoriteProductIds,
      addresses: addresses ?? this.addresses,
      orders: orders ?? this.orders,
      offers: offers ?? this.offers,
      pickupSlots: pickupSlots ?? this.pickupSlots,
      deliverySlots: deliverySlots ?? this.deliverySlots,
      serviceablePincodes: serviceablePincodes ?? this.serviceablePincodes,
      minimumOrderPaise: minimumOrderPaise ?? this.minimumOrderPaise,
      settingsRevision: settingsRevision ?? this.settingsRevision,
      baseDeliveryChargePaise:
          baseDeliveryChargePaise ?? this.baseDeliveryChargePaise,
      freeDeliveryThresholdPaise:
          freeDeliveryThresholdPaise ?? this.freeDeliveryThresholdPaise,
      pickupEnabled: pickupEnabled ?? this.pickupEnabled,
      deliveryEnabled: deliveryEnabled ?? this.deliveryEnabled,
      cashOnDeliveryEnabled:
          cashOnDeliveryEnabled ?? this.cashOnDeliveryEnabled,
      fulfilmentType: fulfilmentType ?? this.fulfilmentType,
      selectedDate: selectedDate ?? this.selectedDate,
      selectedSlotLabel: selectedSlotLabel ?? this.selectedSlotLabel,
      selectedAddressId: selectedAddressId ?? this.selectedAddressId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      deliveryInstructions: deliveryInstructions ?? this.deliveryInstructions,
      selectedOfferCode: clearSelectedOffer
          ? null
          : selectedOfferCode ?? this.selectedOfferCode,
      lastOrderId: clearLastOrder ? null : lastOrderId ?? this.lastOrderId,
    );
  }
}

class StoreController extends Notifier<StoreState> {
  final remoteCheckout = CheckoutAttempt<StoreState>();
  int _lastRemoteLoad = 0;

  StoreState _initialState() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return StoreState(
      categories: DemoStoreData.categories,
      products: DemoStoreData.products,
      addresses: DemoStoreData.addresses,
      orders: _seedOrders(),
      offers: DemoStoreData.offers,
      pickupSlots: DemoStoreData.pickupSlots,
      deliverySlots: DemoStoreData.deliverySlots,
      serviceablePincodes: DemoStoreData.serviceablePincodes,
      selectedDate: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
    );
  }

  @override
  StoreState build() => _initialState();

  void loginDemo({String? email, bool isAdmin = false}) {
    state = state.copyWith(
      isAuthenticated: true,
      isAdminView: isAdmin,
      isAdminAccount: isAdmin,
      profile: CustomerProfile(
        id: 'demo-customer',
        name: 'Ezlin',
        email: email?.trim().isNotEmpty == true
            ? email!.trim()
            : 'ezlin@example.com',
        phone: '+91 98765 43210',
      ),
    );
  }

  void logout() {
    remoteCheckout.reset();
    _lastRemoteLoad = 0;
    // Replace the entire remote state so orders, addresses and staff-only
    // catalogue fields do not remain readable from a signed-out browser tab.
    state = _initialState();
  }

  void setAdminView(bool value) {
    if (value &&
        !state.isAdminAccount &&
        state.profile?.id != 'demo-customer') {
      throw const StoreValidationException('Administrator access required.');
    }
    state = state.copyWith(isAdminView: value);
  }

  void updateProfile(CustomerProfile profile) {
    state = state.copyWith(profile: profile);
  }

  void hydrateFromBackend({
    required CustomerProfile profile,
    required List<ProductCategory> categories,
    required List<Product> products,
    required List<CustomerAddress> addresses,
    required List<CustomerOrder> orders,
    required List<StoreOffer> offers,
    required List<FulfilmentSlot> pickupSlots,
    required List<FulfilmentSlot> deliverySlots,
    required Set<String> serviceablePincodes,
    required int minimumOrderPaise,
    required int baseDeliveryChargePaise,
    required int freeDeliveryThresholdPaise,
    required bool pickupEnabled,
    required bool deliveryEnabled,
    required bool cashOnDeliveryEnabled,
    bool isAdmin = false,
    int loadSequence = 0,
    int settingsRevision = 0,
  }) {
    if (!ref.mounted || (loadSequence > 0 && loadSequence <= _lastRemoteLoad)) {
      return;
    }
    if (loadSequence > 0) _lastRemoteLoad = loadSequence;
    final sameCustomer = state.profile?.id == profile.id;
    final unchangedProducts = listEquals(products, state.products);
    final sameProductScope = sameCustomer && state.isAdminAccount == isAdmin;
    final previousProducts = unchangedProducts
        ? <String, Product>{}
        : {for (final product in state.products) product.id: product};
    final retainFulfilment =
        sameCustomer &&
        (state.fulfilmentType == FulfilmentType.pickup
            ? pickupEnabled
            : deliveryEnabled);
    final fulfilment = retainFulfilment
        ? state.fulfilmentType
        : pickupEnabled
        ? FulfilmentType.pickup
        : FulfilmentType.delivery;
    final selectedSlots = fulfilment == FulfilmentType.pickup
        ? pickupSlots
        : deliverySlots;
    state = state.copyWith(
      profile: profile,
      isAuthenticated: true,
      isAdminView: isAdmin,
      isAdminAccount: isAdmin,
      cartQuantities: sameCustomer ? state.cartQuantities : const {},
      categories: categories,
      products: unchangedProducts
          ? state.products
          : sameProductScope
          ? products
                .map((product) {
                  final current = previousProducts[product.id];
                  return current != null && current.revision > product.revision
                      ? current
                      : product;
                })
                .toList(growable: false)
          : products,
      addresses: addresses,
      orders: orders,
      offers: offers,
      pickupSlots: pickupSlots,
      deliverySlots: deliverySlots,
      serviceablePincodes: serviceablePincodes,
      minimumOrderPaise: minimumOrderPaise,
      settingsRevision: settingsRevision,
      baseDeliveryChargePaise: baseDeliveryChargePaise,
      freeDeliveryThresholdPaise: freeDeliveryThresholdPaise,
      pickupEnabled: pickupEnabled,
      deliveryEnabled: deliveryEnabled,
      cashOnDeliveryEnabled: cashOnDeliveryEnabled,
      fulfilmentType: fulfilment,
      paymentMethod: fulfilment == FulfilmentType.pickup
          ? PaymentMethod.payAtStore
          : cashOnDeliveryEnabled
          ? PaymentMethod.cashOnDelivery
          : AppEnvironment.enableRazorpayPayments
          ? PaymentMethod.online
          : PaymentMethod.cashOnDelivery,
      selectedAddressId:
          sameCustomer &&
              addresses.any((address) => address.id == state.selectedAddressId)
          ? state.selectedAddressId
          : addresses.isEmpty
          ? ''
          : addresses
                .firstWhere(
                  (item) => item.isDefault,
                  orElse: () => addresses.first,
                )
                .id,
      selectedSlotLabel:
          sameCustomer &&
              selectedSlots.any((slot) => slot.label == state.selectedSlotLabel)
          ? state.selectedSlotLabel
          : selectedSlots.isEmpty
          ? ''
          : selectedSlots.first.label,
    );
  }

  bool ownsConfirmedCheckout(String orderId, String? customerId) =>
      ref.mounted &&
      customerId != null &&
      state.isAuthenticated &&
      state.profile?.id == customerId &&
      state.lastOrderId == orderId;

  void finishRemoteCheckout(
    String orderId, {
    Map<String, int>? submittedCart,
    String? customerId,
  }) {
    if (!ref.mounted ||
        (customerId != null && state.profile?.id != customerId) ||
        state.lastOrderId == orderId) {
      return;
    }
    remoteCheckout.reset();
    final remaining = Map<String, int>.from(state.cartQuantities);
    if (submittedCart != null) {
      for (final item in submittedCart.entries) {
        final quantity = (remaining[item.key] ?? 0) - item.value;
        if (quantity > 0) {
          remaining[item.key] = quantity;
        } else {
          remaining.remove(item.key);
        }
      }
    }
    state = state.copyWith(
      cartQuantities: submittedCart == null ? const {} : remaining,
      lastOrderId: orderId,
      deliveryInstructions: '',
      clearSelectedOffer: true,
    );
  }

  void restoreSavedCart(String userId, Map<String, int> quantities) {
    if (!state.isAuthenticated ||
        state.profile?.id != userId ||
        state.isAdminAccount) {
      return;
    }
    state = state.copyWith(cartQuantities: Map.unmodifiable(quantities));
  }

  void addToCart(String productId) {
    final product = state.productById(productId);
    if (product == null || !product.isAvailable) {
      throw const StoreValidationException('This product is unavailable.');
    }
    final current = state.cartQuantities[productId] ?? 0;
    if (current >= product.stockQuantity) {
      throw const StoreValidationException('No additional stock is available.');
    }
    state = state.copyWith(
      cartQuantities: {...state.cartQuantities, productId: current + 1},
    );
  }

  void decrementCart(String productId) {
    final current = state.cartQuantities[productId] ?? 0;
    final updated = {...state.cartQuantities};
    if (current <= 1) {
      updated.remove(productId);
    } else {
      updated[productId] = current - 1;
    }
    state = state.copyWith(cartQuantities: updated);
  }

  /// Commit a pack selection once; preserve cart changes made while it was open.
  void confirmCartSelection({
    required String? expectedUserId,
    required Map<String, int> baseline,
    required Map<String, int> selection,
  }) {
    if (!state.isAuthenticated || state.profile?.id != expectedUserId) {
      throw const StoreValidationException(
        'Your session changed. Please sign in again.',
      );
    }
    final updated = {...state.cartQuantities};
    for (final id in {...baseline.keys, ...selection.keys}) {
      final delta = (selection[id] ?? 0) - (baseline[id] ?? 0);
      if (delta == 0) continue;
      final quantity = max(0, (updated[id] ?? 0) + delta);
      final product = state.productById(id);
      if (delta > 0 &&
          (product == null ||
              !product.isAvailable ||
              quantity > product.stockQuantity)) {
        throw const StoreValidationException(
          'Stock changed. Please adjust your selected quantities.',
        );
      }
      if (quantity == 0) {
        updated.remove(id);
      } else {
        updated[id] = quantity;
      }
    }
    state = state.copyWith(cartQuantities: updated);
  }

  void removeFromCart(String productId) {
    final updated = {...state.cartQuantities}..remove(productId);
    state = state.copyWith(cartQuantities: updated);
  }

  void toggleFavorite(String productId) {
    final favorites = {...state.favoriteProductIds};
    if (!favorites.add(productId)) favorites.remove(productId);
    state = state.copyWith(favoriteProductIds: favorites);
  }

  void setFulfilment(FulfilmentType value) {
    if (value == FulfilmentType.pickup && !state.pickupEnabled) {
      throw const StoreValidationException('Pickup is currently unavailable.');
    }
    if (value == FulfilmentType.delivery && !state.deliveryEnabled) {
      throw const StoreValidationException(
        'Delivery is currently unavailable.',
      );
    }
    final now = DateTime.now();
    state = state.copyWith(
      fulfilmentType: value,
      // Pickup is always associated internally with the day it is placed;
      // customers no longer choose a pickup date.
      selectedDate: value == FulfilmentType.pickup
          ? DateTime(now.year, now.month, now.day)
          : state.selectedDate,
      selectedSlotLabel: value == FulfilmentType.pickup
          ? (state.pickupSlots.isEmpty ? '' : state.pickupSlots.first.label)
          : (state.deliverySlots.isEmpty
                ? ''
                : state.deliverySlots.first.label),
      paymentMethod: value == FulfilmentType.pickup
          ? PaymentMethod.payAtStore
          : PaymentMethod.cashOnDelivery,
    );
  }

  void setFulfilmentDate(DateTime value) {
    state = state.copyWith(selectedDate: value);
  }

  void setSlot(String value) {
    state = state.copyWith(selectedSlotLabel: value);
  }

  void selectAddress(String id) {
    state = state.copyWith(selectedAddressId: id);
  }

  void setDeliveryInstructions(String value) {
    state = state.copyWith(deliveryInstructions: value.trim());
  }

  void setPaymentMethod(PaymentMethod value) {
    if (value == PaymentMethod.online &&
        !AppEnvironment.enableRazorpayPayments) {
      throw const StoreValidationException(
        'Online payments are not available in this release.',
      );
    }
    if (state.fulfilmentType == FulfilmentType.pickup &&
        value == PaymentMethod.cashOnDelivery) {
      throw const StoreValidationException(
        'Payment on delivery is not available for pickup.',
      );
    }
    if (state.fulfilmentType == FulfilmentType.delivery &&
        value == PaymentMethod.payAtStore) {
      throw const StoreValidationException(
        'Pay at store is only available for pickup.',
      );
    }
    if (value == PaymentMethod.cashOnDelivery && !state.cashOnDeliveryEnabled) {
      throw const StoreValidationException(
        'Payment on delivery is currently unavailable.',
      );
    }
    state = state.copyWith(paymentMethod: value);
  }

  void applyOffer(String code) {
    final offer = state.offerByCode(code);
    if (offer == null) {
      throw const StoreValidationException('Offer code was not found.');
    }
    final reason = state.offerIneligibilityReason(offer);
    if (reason != null) throw StoreValidationException(reason);
    state = state.copyWith(selectedOfferCode: offer.code);
  }

  void removeOffer() => state = state.copyWith(clearSelectedOffer: true);

  void addAddress(CustomerAddress address) {
    state = state.copyWith(
      addresses: [...state.addresses, address],
      selectedAddressId: address.id,
    );
  }

  void updateAddress(CustomerAddress address) {
    state = state.copyWith(
      addresses: state.addresses
          .map((item) => item.id == address.id ? address : item)
          .toList(growable: false),
    );
  }

  void deleteAddress(String addressId) {
    final addresses = state.addresses
        .where((item) => item.id != addressId)
        .toList(growable: false);
    state = state.copyWith(
      addresses: addresses,
      selectedAddressId: state.selectedAddressId == addressId
          ? (addresses.isEmpty ? '' : addresses.first.id)
          : state.selectedAddressId,
    );
  }

  void setDefaultAddress(String addressId) {
    state = state.copyWith(
      addresses: state.addresses
          .map((item) => item.copyWith(isDefault: item.id == addressId))
          .toList(growable: false),
      selectedAddressId: addressId,
    );
  }

  String placeOrder() {
    if (state.cartItems.isEmpty) {
      throw const StoreValidationException('Your cart is empty.');
    }
    if (state.subtotalPaise < state.minimumOrderPaise) {
      throw StoreValidationException(
        'Minimum order amount is ₹${state.minimumOrderPaise ~/ 100}.',
      );
    }
    for (final item in state.cartItems) {
      if (!item.product.isAvailable ||
          item.quantity > item.product.stockQuantity) {
        throw StoreValidationException(
          '${item.product.name} no longer has enough stock.',
        );
      }
    }
    final offer = state.selectedOffer;
    if (state.selectedOfferCode != null && offer == null) {
      throw const StoreValidationException(
        'The selected offer is no longer available.',
      );
    }
    if (offer != null) {
      final reason = state.offerIneligibilityReason(offer);
      if (reason != null) throw StoreValidationException(reason);
    }
    final freeProduct = state.freeOfferProduct;
    final address = state.selectedAddress;
    if (state.fulfilmentType == FulfilmentType.delivery) {
      if (address == null) {
        throw const StoreValidationException('Select a delivery address.');
      }
      if (!state.serviceablePincodes.contains(address.pincode)) {
        throw StoreValidationException(
          'Delivery is not available for PIN ${address.pincode}.',
        );
      }
    }

    final timestamp = DateTime.now();
    final id = 'KOY${timestamp.millisecondsSinceEpoch.toString().substring(5)}';
    final orderItems = state.cartItems
        .map(
          (item) => OrderItemSnapshot(
            productId: item.product.id,
            name: item.product.name,
            unit: item.product.unit,
            unitPricePaise: item.product.effectivePricePaise,
            quantity: item.quantity,
            visualKey: item.product.visualKey,
          ),
        )
        .toList();
    if (offer != null && freeProduct != null) {
      orderItems.add(
        OrderItemSnapshot(
          productId: freeProduct.id,
          name: freeProduct.name,
          unit: freeProduct.unit,
          unitPricePaise: 0,
          quantity: offer.freeQuantity,
          visualKey: freeProduct.visualKey,
          isFreeOfferItem: true,
        ),
      );
    }
    final order = CustomerOrder(
      id: id,
      items: orderItems,
      fulfilmentType: state.fulfilmentType,
      fulfilmentDate: state.fulfilmentType == FulfilmentType.pickup
          ? DateTime(timestamp.year, timestamp.month, timestamp.day)
          : state.selectedDate,
      slotLabel: state.selectedSlotLabel,
      addressText: state.fulfilmentType == FulfilmentType.delivery
          ? address?.formatted
          : null,
      deliveryPin: state.fulfilmentType == FulfilmentType.delivery
          ? address?.deliveryPin
          : null,
      subtotalPaise: state.subtotalPaise,
      deliveryChargePaise: state.deliveryChargePaise,
      discountPaise: state.savingsPaise + state.offerDiscountPaise,
      totalPaise: state.totalPaise,
      paymentMethod: state.paymentMethod,
      paymentStatus: state.paymentMethod == PaymentMethod.online
          ? PaymentStatus.paid
          : PaymentStatus.pending,
      status: OrderStatus.placed,
      deliveryInstructions: state.deliveryInstructions,
      customerName: state.profile?.name ?? '',
      customerPhone: state.profile?.phone ?? '',
      deliveryRecipientName: state.fulfilmentType == FulfilmentType.delivery
          ? address?.recipientName ?? ''
          : '',
      deliveryRecipientPhone: state.fulfilmentType == FulfilmentType.delivery
          ? address?.phone ?? ''
          : '',
      createdAt: timestamp,
      paidAt: state.paymentMethod == PaymentMethod.online ? timestamp : null,
      offerCode: offer?.code,
      offerTitle: offer?.title,
      offerDiscountPaise: state.offerDiscountPaise,
    );

    final purchased = {...state.cartQuantities};
    if (offer != null && freeProduct != null) {
      purchased[freeProduct.id] =
          (purchased[freeProduct.id] ?? 0) + offer.freeQuantity;
    }
    final updatedProducts = state.products
        .map((product) {
          final quantity = purchased[product.id] ?? 0;
          return quantity == 0
              ? product
              : product.copyWith(
                  stockQuantity: max(0, product.stockQuantity - quantity),
                  revision: product.revision + 1,
                );
        })
        .toList(growable: false);

    state = state.copyWith(
      products: updatedProducts,
      orders: [order, ...state.orders],
      cartQuantities: const {},
      lastOrderId: id,
      deliveryInstructions: '',
      clearSelectedOffer: true,
    );
    return id;
  }

  void cancelOrder(String orderId) {
    final order = state.orders.firstWhere((item) => item.id == orderId);
    if (order.status != OrderStatus.placed &&
        order.status != OrderStatus.confirmed) {
      throw const StoreValidationException(
        'Orders cannot be cancelled after preparation begins.',
      );
    }
    state = state.copyWith(
      products: _productsWithRestoredStock(order),
      orders: state.orders
          .map(
            (item) => item.id == orderId
                ? item.copyWith(status: OrderStatus.cancelled)
                : item,
          )
          .toList(growable: false),
    );
  }

  List<Product> _productsWithRestoredStock(CustomerOrder order) => state
      .products
      .map((product) {
        var restored = 0;
        for (final item in order.items) {
          if (item.productId == product.id) restored += item.quantity;
        }
        return restored == 0
            ? product
            : product.copyWith(
                stockQuantity: product.stockQuantity + restored,
                revision: product.revision + 1,
              );
      })
      .toList(growable: false);

  void reorder(String orderId) {
    final order = state.orders.firstWhere((item) => item.id == orderId);
    final quantities = {...state.cartQuantities};
    for (final item in order.items) {
      if (item.isFreeOfferItem) continue;
      final product = state.productById(item.productId);
      if (product != null && product.isAvailable) {
        quantities[item.productId] = min(item.quantity, product.stockQuantity);
      }
    }
    state = state.copyWith(cartQuantities: quantities);
  }

  void advanceOrder(String orderId) {
    _updateOrder(orderId, (order) {
      final next = switch ((order.fulfilmentType, order.status)) {
        (
          FulfilmentType.pickup,
          OrderStatus.placed || OrderStatus.confirmed || OrderStatus.preparing,
        ) =>
          OrderStatus.readyForPickup,
        (FulfilmentType.pickup, OrderStatus.readyForPickup) =>
          OrderStatus.collected,
        (FulfilmentType.delivery, OrderStatus.placed) => OrderStatus.confirmed,
        (FulfilmentType.delivery, OrderStatus.confirmed) =>
          OrderStatus.preparing,
        (FulfilmentType.delivery, OrderStatus.preparing) =>
          OrderStatus.readyForDispatch,
        (FulfilmentType.delivery, OrderStatus.readyForDispatch) =>
          OrderStatus.outForDelivery,
        (FulfilmentType.delivery, OrderStatus.outForDelivery) =>
          OrderStatus.delivered,
        _ => order.status,
      };
      return order.copyWith(status: next);
    });
  }

  void adminRejectOrder(String orderId) =>
      _adminCloseOrder(orderId, nextStatus: OrderStatus.rejected);

  void adminCancelOrder(String orderId) =>
      _adminCloseOrder(orderId, nextStatus: OrderStatus.cancelled);

  void _adminCloseOrder(String orderId, {required OrderStatus nextStatus}) {
    if (!state.isAdminView) {
      throw const StoreValidationException('Administrator access required.');
    }
    final order = state.orders.firstWhere((item) => item.id == orderId);
    final valid = switch (nextStatus) {
      OrderStatus.rejected => order.status == OrderStatus.placed,
      OrderStatus.cancelled => order.status == OrderStatus.confirmed,
      _ => false,
    };
    if (!valid) {
      throw const StoreValidationException(
        'This order can no longer be closed from its current status.',
      );
    }
    state = state.copyWith(
      products: _productsWithRestoredStock(order),
      orders: state.orders
          .map(
            (item) =>
                item.id == orderId ? item.copyWith(status: nextStatus) : item,
          )
          .toList(growable: false),
    );
  }

  void adminMarkOrderPaid(String orderId) {
    if (!state.isAdminView) {
      throw const StoreValidationException('Administrator access required.');
    }
    final order = state.orders.firstWhere((item) => item.id == orderId);
    final supportedMethod = {
      PaymentMethod.cashOnDelivery,
      PaymentMethod.payAtStore,
    }.contains(order.paymentMethod);
    final collectionStage = switch (order.paymentMethod) {
      PaymentMethod.payAtStore => {
        OrderStatus.readyForPickup,
        OrderStatus.collected,
      }.contains(order.status),
      PaymentMethod.cashOnDelivery => {
        OrderStatus.outForDelivery,
        OrderStatus.delivered,
      }.contains(order.status),
      PaymentMethod.online => false,
    };
    if (!supportedMethod ||
        order.paymentStatus != PaymentStatus.pending ||
        !collectionStage) {
      throw const StoreValidationException(
        'Payment cannot be recorded at this order stage.',
      );
    }
    _updateOrder(
      orderId,
      (item) => item.copyWith(
        paymentStatus: PaymentStatus.paid,
        paidAt: DateTime.now(),
      ),
    );
  }

  void adminSaveProduct(Product product) {
    if (!state.isAdminView) {
      throw const StoreValidationException('Administrator access required.');
    }
    final previous = state.productById(product.id);
    final exists = previous != null;
    if (previous != null && previous.revision != product.revision) {
      throw const StoreValidationException(
        'This product changed while you were editing it. Refresh inventory and try again.',
      );
    }
    final saved = product.copyWith(revision: (previous?.revision ?? -1) + 1);
    final products = exists
        ? state.products
              .map((item) => item.id == product.id ? saved : item)
              .toList(growable: false)
        : [saved, ...state.products];
    state = state.copyWith(products: products);
  }

  void adminSaveOffer(StoreOffer offer) {
    if (!state.isAdminView) {
      throw const StoreValidationException('Administrator access required.');
    }
    if (!offer.hasDiscount && !offer.hasFreeProduct) {
      throw const StoreValidationException(
        'Choose a discount, a free product, or both.',
      );
    }
    if (offer.minimumSubtotalPaise < 0 || offer.perCustomerLimit < 1) {
      throw const StoreValidationException('Offer settings are invalid.');
    }
    final duplicateCode = state.offers.any(
      (item) =>
          item.id != offer.id &&
          item.code.toUpperCase() == offer.code.toUpperCase(),
    );
    if (duplicateCode) {
      throw const StoreValidationException('That offer code already exists.');
    }
    final previous = state.offers
        .where((item) => item.id == offer.id)
        .firstOrNull;
    if (previous != null && previous.revision != offer.revision) {
      throw const StoreValidationException(
        'This offer changed while you were editing. Refresh and try again.',
      );
    }
    final saved = offer.copyWith(revision: (previous?.revision ?? -1) + 1);
    final exists = previous != null;
    state = state.copyWith(
      offers: exists
          ? state.offers
                .map((item) => item.id == offer.id ? saved : item)
                .toList(growable: false)
          : [saved, ...state.offers],
    );
  }

  void adminUpdateOrderPricing({
    required int minimumOrderPaise,
    required int deliveryChargePaise,
    required int freeDeliveryThresholdPaise,
    int? expectedRevision,
  }) {
    if (expectedRevision != null &&
        expectedRevision != state.settingsRevision) {
      throw const StoreValidationException(
        'Order pricing changed while you were editing. Refresh and try again.',
      );
    }
    if (!state.isAdminView) {
      throw const StoreValidationException('Administrator access required.');
    }
    if (deliveryChargePaise < 0 || deliveryChargePaise > 1000000) {
      throw const StoreValidationException(
        'Delivery charge must be between ₹0 and ₹10,000.',
      );
    }
    if (minimumOrderPaise < 0 || minimumOrderPaise > 100000000) {
      throw const StoreValidationException(
        'Minimum order is outside the allowed range.',
      );
    }
    if (freeDeliveryThresholdPaise < 0 ||
        freeDeliveryThresholdPaise > 100000000) {
      throw const StoreValidationException(
        'Free-delivery threshold is outside the allowed range.',
      );
    }
    state = state.copyWith(
      minimumOrderPaise: minimumOrderPaise,
      baseDeliveryChargePaise: deliveryChargePaise,
      settingsRevision: state.settingsRevision + 1,
      freeDeliveryThresholdPaise: freeDeliveryThresholdPaise,
    );
  }

  void _updateOrder(
    String id,
    CustomerOrder Function(CustomerOrder order) transform,
  ) {
    state = state.copyWith(
      orders: state.orders
          .map((order) => order.id == id ? transform(order) : order)
          .toList(growable: false),
    );
  }

  List<CustomerOrder> _seedOrders() {
    final now = DateTime.now();
    final availableProducts = DemoStoreData.products
        .where((product) => product.isAvailable)
        .take(4)
        .toList(growable: false);
    if (availableProducts.isEmpty) return const [];

    OrderItemSnapshot snapshot(int index, {int quantity = 1}) {
      final product = availableProducts[index % availableProducts.length];
      return OrderItemSnapshot(
        productId: product.id,
        name: product.name,
        unit: product.unit,
        unitPricePaise: product.effectivePricePaise,
        quantity: min(quantity, product.stockQuantity),
        visualKey: product.visualKey,
      );
    }

    int subtotal(List<OrderItemSnapshot> items) =>
        items.fold(0, (total, item) => total + item.totalPaise);

    final pickupItems = [snapshot(0, quantity: 2), snapshot(1)];
    final deliveryItems = [snapshot(2), snapshot(3)];
    final pickupSubtotal = subtotal(pickupItems);
    final deliverySubtotal = subtotal(deliveryItems);
    return [
      CustomerOrder(
        id: 'KOY34621',
        items: [snapshot(2)],
        fulfilmentType: FulfilmentType.delivery,
        fulfilmentDate: now,
        slotLabel: '6:00 PM – 9:00 PM',
        addressText: '18, Masab Tank Road, Hyderabad – 500028',
        subtotalPaise: deliveryItems.first.totalPaise,
        deliveryChargePaise: 4900,
        discountPaise: 0,
        totalPaise: deliveryItems.first.totalPaise + 4900,
        paymentMethod: PaymentMethod.cashOnDelivery,
        paymentStatus: PaymentStatus.pending,
        status: OrderStatus.placed,
        deliveryInstructions: 'Call on arrival; use the side gate.',
        customerName: 'Ayesha Rahman',
        customerPhone: '+91 98490 11223',
        deliveryRecipientName: 'Ayesha Rahman',
        deliveryRecipientPhone: '+91 98490 11223',
        createdAt: now.subtract(const Duration(minutes: 25)),
      ),
      CustomerOrder(
        id: 'KOY34620',
        items: [snapshot(3)],
        fulfilmentType: FulfilmentType.delivery,
        fulfilmentDate: now,
        slotLabel: '6:00 PM – 9:00 PM',
        addressText: '7, Banjara Hills Road 12, Hyderabad – 500034',
        subtotalPaise: deliveryItems.last.totalPaise,
        deliveryChargePaise: 4900,
        discountPaise: 0,
        totalPaise: deliveryItems.last.totalPaise + 4900,
        paymentMethod: PaymentMethod.cashOnDelivery,
        paymentStatus: PaymentStatus.pending,
        status: OrderStatus.confirmed,
        deliveryInstructions: 'Ring the bell once; leave with the guard.',
        customerName: 'Imran Khan',
        customerPhone: '+91 97000 44556',
        deliveryRecipientName: 'Nazia Khan',
        deliveryRecipientPhone: '+91 97000 77889',
        createdAt: now.subtract(const Duration(minutes: 45)),
      ),
      CustomerOrder(
        id: 'KOY34619',
        items: pickupItems,
        fulfilmentType: FulfilmentType.pickup,
        fulfilmentDate: now,
        slotLabel: 'Store hours',
        subtotalPaise: pickupSubtotal,
        deliveryChargePaise: 0,
        discountPaise: 0,
        totalPaise: pickupSubtotal,
        paymentMethod: PaymentMethod.payAtStore,
        paymentStatus: PaymentStatus.pending,
        status: OrderStatus.readyForPickup,
        customerName: 'Ezlin',
        customerPhone: '+91 98765 43210',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      CustomerOrder(
        id: 'KOY34572',
        items: deliveryItems,
        fulfilmentType: FulfilmentType.delivery,
        fulfilmentDate: now.subtract(const Duration(days: 8)),
        slotLabel: '6:00 PM – 9:00 PM',
        addressText: '12, Lake View Colony, Hyderabad – 500034',
        subtotalPaise: deliverySubtotal,
        deliveryChargePaise: 4900,
        discountPaise: 0,
        totalPaise: deliverySubtotal + 4900,
        paymentMethod: PaymentMethod.online,
        paymentStatus: PaymentStatus.paid,
        status: OrderStatus.delivered,
        customerName: 'Ezlin',
        customerPhone: '+91 98765 43210',
        deliveryRecipientName: 'Ezlin',
        deliveryRecipientPhone: '+91 98765 43210',
        createdAt: now.subtract(const Duration(days: 9)),
        paidAt: now.subtract(const Duration(days: 9)),
      ),
    ];
  }
}

final storeProvider = NotifierProvider<StoreController, StoreState>(
  StoreController.new,
);
