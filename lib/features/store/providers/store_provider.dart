import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../cart/models/cart_item.dart';
import '../../checkout/models/checkout_models.dart';
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
    required this.pickupSlots,
    required this.deliverySlots,
    required this.serviceablePincodes,
    this.minimumOrderPaise = 19900,
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
  final List<FulfilmentSlot> pickupSlots;
  final List<FulfilmentSlot> deliverySlots;
  final Set<String> serviceablePincodes;
  final int minimumOrderPaise;
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
  final String? lastOrderId;

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
  int get totalPaise => subtotalPaise + deliveryChargePaise;

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
    List<FulfilmentSlot>? pickupSlots,
    List<FulfilmentSlot>? deliverySlots,
    Set<String>? serviceablePincodes,
    int? minimumOrderPaise,
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
    String? lastOrderId,
    bool clearProfile = false,
    bool clearLastOrder = false,
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
      pickupSlots: pickupSlots ?? this.pickupSlots,
      deliverySlots: deliverySlots ?? this.deliverySlots,
      serviceablePincodes: serviceablePincodes ?? this.serviceablePincodes,
      minimumOrderPaise: minimumOrderPaise ?? this.minimumOrderPaise,
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
      lastOrderId: clearLastOrder ? null : lastOrderId ?? this.lastOrderId,
    );
  }
}

class StoreController extends Notifier<StoreState> {
  StoreState _initialState() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return StoreState(
      categories: DemoStoreData.categories,
      products: DemoStoreData.products,
      addresses: DemoStoreData.addresses,
      orders: _seedOrders(),
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
  }) {
    final fulfilment = pickupEnabled
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
      categories: categories,
      products: products,
      addresses: addresses,
      orders: orders,
      pickupSlots: pickupSlots,
      deliverySlots: deliverySlots,
      serviceablePincodes: serviceablePincodes,
      minimumOrderPaise: minimumOrderPaise,
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
      selectedAddressId: addresses.isEmpty
          ? ''
          : addresses
                .firstWhere(
                  (item) => item.isDefault,
                  orElse: () => addresses.first,
                )
                .id,
      selectedSlotLabel: selectedSlots.isEmpty ? '' : selectedSlots.first.label,
    );
  }

  void finishRemoteCheckout(String orderId) {
    state = state.copyWith(
      cartQuantities: const {},
      lastOrderId: orderId,
      deliveryInstructions: '',
    );
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
        .toList(growable: false);
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
      subtotalPaise: state.subtotalPaise,
      deliveryChargePaise: state.deliveryChargePaise,
      discountPaise: state.savingsPaise,
      totalPaise: state.totalPaise,
      paymentMethod: state.paymentMethod,
      paymentStatus: state.paymentMethod == PaymentMethod.online
          ? PaymentStatus.paid
          : PaymentStatus.pending,
      status: OrderStatus.placed,
      deliveryInstructions: state.deliveryInstructions,
      createdAt: timestamp,
    );

    final purchased = {...state.cartQuantities};
    final updatedProducts = state.products
        .map((product) {
          final quantity = purchased[product.id] ?? 0;
          return quantity == 0
              ? product
              : product.copyWith(
                  stockQuantity: max(0, product.stockQuantity - quantity),
                );
        })
        .toList(growable: false);

    state = state.copyWith(
      products: updatedProducts,
      orders: [order, ...state.orders],
      cartQuantities: const {},
      lastOrderId: id,
      deliveryInstructions: '',
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
    final restoredProducts = state.products
        .map((product) {
          var restored = 0;
          for (final item in order.items) {
            if (item.productId == product.id) restored += item.quantity;
          }
          return restored == 0
              ? product
              : product.copyWith(
                  stockQuantity: product.stockQuantity + restored,
                );
        })
        .toList(growable: false);
    state = state.copyWith(
      products: restoredProducts,
      orders: state.orders
          .map(
            (item) => item.id == orderId
                ? item.copyWith(status: OrderStatus.cancelled)
                : item,
          )
          .toList(growable: false),
    );
  }

  void reorder(String orderId) {
    final order = state.orders.firstWhere((item) => item.id == orderId);
    final quantities = {...state.cartQuantities};
    for (final item in order.items) {
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

  void adminSaveProduct(Product product) {
    if (!state.isAdminView) {
      throw const StoreValidationException('Administrator access required.');
    }
    final exists = state.products.any((item) => item.id == product.id);
    final products = exists
        ? state.products
              .map((item) => item.id == product.id ? product : item)
              .toList(growable: false)
        : [product, ...state.products];
    state = state.copyWith(products: products);
  }

  void adminUpdateDeliveryPricing({
    required int deliveryChargePaise,
    required int freeDeliveryThresholdPaise,
  }) {
    if (!state.isAdminView) {
      throw const StoreValidationException('Administrator access required.');
    }
    if (deliveryChargePaise < 0 || deliveryChargePaise > 1000000) {
      throw const StoreValidationException(
        'Delivery charge must be between ₹0 and ₹10,000.',
      );
    }
    if (freeDeliveryThresholdPaise < 0 ||
        freeDeliveryThresholdPaise > 100000000) {
      throw const StoreValidationException(
        'Free-delivery threshold is outside the allowed range.',
      );
    }
    state = state.copyWith(
      baseDeliveryChargePaise: deliveryChargePaise,
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
        createdAt: now.subtract(const Duration(days: 9)),
      ),
    ];
  }
}

final storeProvider = NotifierProvider<StoreController, StoreState>(
  StoreController.new,
);
