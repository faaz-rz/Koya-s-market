import 'package:supabase_flutter/supabase_flutter.dart';

import '../../checkout/models/checkout_models.dart';
import '../../orders/models/order.dart';
import '../../products/models/category.dart';
import '../../products/models/product.dart';
import '../../products/models/product_image_upload.dart';
import '../../profile/models/customer_profile.dart';
import '../providers/store_provider.dart';

class RemoteStoreBundle {
  const RemoteStoreBundle({
    required this.profile,
    required this.categories,
    required this.products,
    required this.addresses,
    required this.orders,
    required this.pickupSlots,
    required this.deliverySlots,
    required this.isAdmin,
    required this.serviceablePincodes,
    required this.minimumOrderPaise,
    required this.baseDeliveryChargePaise,
    required this.freeDeliveryThresholdPaise,
    required this.pickupEnabled,
    required this.deliveryEnabled,
    required this.cashOnDeliveryEnabled,
  });

  final CustomerProfile profile;
  final List<ProductCategory> categories;
  final List<Product> products;
  final List<CustomerAddress> addresses;
  final List<CustomerOrder> orders;
  final List<FulfilmentSlot> pickupSlots;
  final List<FulfilmentSlot> deliverySlots;
  final bool isAdmin;
  final Set<String> serviceablePincodes;
  final int minimumOrderPaise;
  final int baseDeliveryChargePaise;
  final int freeDeliveryThresholdPaise;
  final bool pickupEnabled;
  final bool deliveryEnabled;
  final bool cashOnDeliveryEnabled;
}

class SupabaseStoreRepository {
  SupabaseStoreRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<RemoteStoreBundle> loadStore() async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Authentication required.');

    final isAdmin = await _client.rpc('is_admin') as bool? ?? false;
    final profileRow = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    final categoryRows = await _client
        .from('categories')
        .select()
        .eq('active', true)
        .order('sort_order');
    final productRows = await _loadProductRows(includeInactive: isAdmin);
    final addressRows = await _client
        .from('addresses')
        .select()
        .eq('user_id', user.id)
        .order('is_default', ascending: false);
    final slotRows = await _client
        .from('fulfilment_slots')
        .select()
        .eq('active', true)
        .order('sort_order');
    final settingsRow = await _client
        .from('store_settings')
        .select()
        .eq('id', 1)
        .single();
    final pincodeRows = await _client
        .from('serviceable_pincodes')
        .select('pincode')
        .eq('active', true);
    final orderRows = isAdmin
        ? await _client
              .from('orders')
              .select('*, order_items(*)')
              .order('created_at', ascending: false)
        : await _client
              .from('orders')
              .select('*, order_items(*)')
              .eq('user_id', user.id)
              .order('created_at', ascending: false);

    final categories = categoryRows
        .map(
          (row) => ProductCategory(
            id: row['id'] as String,
            name: row['name'] as String,
            visualKey: _categoryVisual(row['name'] as String),
          ),
        )
        .toList(growable: false);
    final categoryVisuals = {
      for (final category in categories) category.id: category.visualKey,
    };
    final products = productRows
        .where((row) => categoryVisuals.containsKey(row['category_id']))
        .map((row) {
          final imagePath = row['image_path'] as String?;
          final externalImageUrl = row['external_image_url'] as String?;
          final available = row['available'] as bool? ?? true;
          return Product(
            id: row['id'] as String,
            categoryId: row['category_id'] as String,
            name: row['name'] as String,
            description: row['description'] as String? ?? '',
            unit: row['unit'] as String,
            pricePaise: row['price_paise'] as int,
            discountPricePaise: row['discount_price_paise'] as int?,
            stockQuantity: available ? row['stock_quantity'] as int : 0,
            visualKey: categoryVisuals[row['category_id']] ?? 'grocery',
            subcategory: row['subcategory'] as String? ?? '',
            brand: row['brand'] as String? ?? '',
            billingName: row['source_product_name'] as String? ?? '',
            printName: row['source_print_name'] as String? ?? '',
            itemCode: row['source_item_code'] as String? ?? '',
            barcode: row['barcode'] as String? ?? '',
            imageUrl: imagePath == null || imagePath.isEmpty
                ? externalImageUrl
                : _client.storage
                      .from('product-images')
                      .getPublicUrl(imagePath),
            imagePath: imagePath ?? '',
            imageAttribution: row['image_attribution'] as String? ?? '',
            featured: row['featured'] as bool? ?? false,
          );
        })
        .toList(growable: false);
    final addresses = addressRows
        .map(
          (row) => CustomerAddress(
            id: row['id'] as String,
            label: row['label'] as String,
            recipientName: row['recipient_name'] as String,
            phone: row['phone'] as String,
            line1: row['line1'] as String,
            city: row['city'] as String,
            pincode: row['pincode'] as String,
            instructions: row['instructions'] as String? ?? '',
            isDefault: row['is_default'] as bool? ?? false,
          ),
        )
        .toList(growable: false);
    final slots = slotRows
        .map(
          (row) => FulfilmentSlot(
            id: row['id'] as String,
            label: row['label'] as String,
          ),
        )
        .toList(growable: false);
    final pickupSlotIds = slotRows
        .where((row) => row['fulfilment_type'] == 'pickup')
        .map((row) => row['id'] as String)
        .toSet();
    final orders = orderRows.map(_orderFromRow).toList(growable: false);
    final metadataName = user.userMetadata?['full_name'] as String?;
    return RemoteStoreBundle(
      profile: CustomerProfile(
        id: user.id,
        name: (profileRow?['full_name'] as String?)?.trim().isNotEmpty == true
            ? profileRow!['full_name'] as String
            : metadataName?.trim().isNotEmpty == true
            ? metadataName!
            : 'Koyas customer',
        email: user.email ?? '',
        phone: profileRow?['phone'] as String? ?? user.phone ?? '',
      ),
      categories: categories,
      products: products,
      addresses: addresses,
      orders: orders,
      pickupSlots: slots
          .where((slot) => pickupSlotIds.contains(slot.id))
          .toList(growable: false),
      deliverySlots: slots
          .where((slot) => !pickupSlotIds.contains(slot.id))
          .toList(growable: false),
      isAdmin: isAdmin,
      serviceablePincodes: pincodeRows
          .map((row) => row['pincode'] as String)
          .toSet(),
      minimumOrderPaise: settingsRow['minimum_order_paise'] as int,
      baseDeliveryChargePaise: settingsRow['delivery_charge_paise'] as int,
      freeDeliveryThresholdPaise:
          settingsRow['free_delivery_threshold_paise'] as int,
      pickupEnabled: settingsRow['pickup_enabled'] as bool,
      deliveryEnabled: settingsRow['delivery_enabled'] as bool,
      cashOnDeliveryEnabled: settingsRow['cash_on_delivery_enabled'] as bool,
    );
  }

  Future<List<Map<String, dynamic>>> _loadProductRows({
    required bool includeInactive,
  }) async {
    const pageSize = 1000;
    final products = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      final page = includeInactive
          ? await _client
                .from('products')
                .select()
                .order('available', ascending: false)
                .order('name')
                .order('id')
                .range(offset, offset + pageSize - 1)
          : await _client
                .from('products')
                .select()
                .eq('active', true)
                .order('available', ascending: false)
                .order('name')
                .order('id')
                .range(offset, offset + pageSize - 1);
      products.addAll(page.cast<Map<String, dynamic>>());
      if (page.length < pageSize) break;
    }
    return products;
  }

  Future<String> placeOrder({
    required StoreState store,
    required String idempotencyKey,
  }) async {
    final slots = store.fulfilmentType == FulfilmentType.pickup
        ? store.pickupSlots
        : store.deliverySlots;
    FulfilmentSlot? selectedSlot;
    for (final slot in slots) {
      if (slot.label == store.selectedSlotLabel) selectedSlot = slot;
    }
    if (selectedSlot == null) {
      throw const StoreValidationException('Select a valid fulfilment slot.');
    }
    // Pickup has no customer-selected date. PostgreSQL keeps a fulfilment_date
    // for compatibility, so pickup orders use the day they are placed.
    final requestedDate = store.fulfilmentType == FulfilmentType.pickup
        ? DateTime.now()
        : store.selectedDate;
    final response = await _client.rpc(
      'place_order',
      params: {
        'requested_items': store.cartItems
            .map(
              (item) => {
                'product_id': item.product.id,
                'quantity': item.quantity,
              },
            )
            .toList(),
        'requested_fulfilment': store.fulfilmentType.name,
        'requested_address_id': store.fulfilmentType == FulfilmentType.delivery
            ? store.selectedAddressId
            : null,
        'requested_date': requestedDate.toIso8601String().split('T').first,
        'requested_slot_id': selectedSlot.id,
        'requested_payment': _paymentMethodToDatabase(store.paymentMethod),
        'requested_instructions': store.deliveryInstructions,
        'requested_idempotency_key': idempotencyKey,
      },
    );
    return response as String;
  }

  Future<CustomerAddress> addAddress(CustomerAddress address) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Authentication required.');
    if (address.isDefault) {
      await _client
          .from('addresses')
          .update({'is_default': false})
          .eq('user_id', user.id);
    }
    final row = await _client
        .from('addresses')
        .insert({
          'user_id': user.id,
          'label': address.label,
          'recipient_name': address.recipientName,
          'phone': address.phone,
          'line1': address.line1,
          'city': address.city,
          'pincode': address.pincode,
          'instructions': address.instructions,
          'is_default': address.isDefault,
        })
        .select()
        .single();
    return CustomerAddress(
      id: row['id'] as String,
      label: row['label'] as String,
      recipientName: row['recipient_name'] as String,
      phone: row['phone'] as String,
      line1: row['line1'] as String,
      city: row['city'] as String,
      pincode: row['pincode'] as String,
      instructions: row['instructions'] as String? ?? '',
      isDefault: row['is_default'] as bool? ?? false,
    );
  }

  Future<CustomerProfile> updateProfile(CustomerProfile profile) async {
    final row = await _client
        .from('profiles')
        .update({'full_name': profile.name, 'phone': profile.phone})
        .eq('id', profile.id)
        .select()
        .single();
    return profile.copyWith(
      name: row['full_name'] as String,
      phone: row['phone'] as String? ?? '',
    );
  }

  Future<void> saveProduct(Product product, {ProductImageUpload? image}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Authentication required.');

    String? uploadedPath;
    if (image != null) {
      uploadedPath =
          'products/${user.id}/${DateTime.now().microsecondsSinceEpoch}.${image.extension}';
      await _client.storage
          .from('product-images')
          .uploadBinary(
            uploadedPath,
            image.bytes,
            fileOptions: FileOptions(
              cacheControl: '31536000',
              contentType: image.contentType,
            ),
          );
    }

    try {
      await _client.rpc(
        'admin_save_product',
        params: {
          'target_product_id': _isUuid(product.id) ? product.id : null,
          'product_category_id': product.categoryId,
          'product_name': product.name,
          'product_description': product.description,
          'product_unit': product.unit,
          'product_price_paise': product.pricePaise,
          'product_discount_price_paise': product.discountPricePaise,
          'product_stock_quantity': product.stockQuantity,
          'product_featured': product.featured,
          'product_subcategory': product.subcategory,
          'product_brand': product.brand,
          'product_image_path': uploadedPath,
        },
      );
    } catch (_) {
      if (uploadedPath != null) {
        try {
          await _client.storage.from('product-images').remove([uploadedPath]);
        } catch (_) {
          // The unreferenced object can be cleaned up later if rollback fails.
        }
      }
      rethrow;
    }

    if (uploadedPath != null &&
        product.imagePath.isNotEmpty &&
        product.imagePath != uploadedPath) {
      try {
        await _client.storage.from('product-images').remove([
          product.imagePath,
        ]);
      } catch (_) {
        // The new product image is already saved; stale-image cleanup can retry.
      }
    }
  }

  /// Sets the client's counted on-hand quantity without overwriting price,
  /// name, or other product fields.
  Future<int> setProductStock(String productId, int quantity) async {
    if (!_isUuid(productId)) {
      throw ArgumentError.value(productId, 'productId', 'Expected a UUID');
    }
    final result = await _client.rpc(
      'admin_set_product_stock',
      params: {'target_product_id': productId, 'requested_stock': quantity},
    );
    return (result as num).toInt();
  }

  /// Applies quick +/- stock controls atomically so a simultaneous order does
  /// not get overwritten by an admin page holding an older quantity.
  Future<int> adjustProductStock(String productId, int delta) async {
    if (!_isUuid(productId)) {
      throw ArgumentError.value(productId, 'productId', 'Expected a UUID');
    }
    final result = await _client.rpc(
      'admin_adjust_product_stock',
      params: {'target_product_id': productId, 'stock_delta': delta},
    );
    return (result as num).toInt();
  }

  Future<void> advanceOrder(CustomerOrder order) async {
    final next = switch ((order.fulfilmentType, order.status)) {
      (
        FulfilmentType.pickup,
        OrderStatus.placed || OrderStatus.confirmed || OrderStatus.preparing,
      ) =>
        OrderStatus.readyForPickup,
      (FulfilmentType.pickup, OrderStatus.readyForPickup) =>
        OrderStatus.collected,
      (FulfilmentType.delivery, OrderStatus.placed) => OrderStatus.confirmed,
      (FulfilmentType.delivery, OrderStatus.confirmed) => OrderStatus.preparing,
      (FulfilmentType.delivery, OrderStatus.preparing) =>
        OrderStatus.readyForDispatch,
      (FulfilmentType.delivery, OrderStatus.readyForDispatch) =>
        OrderStatus.outForDelivery,
      (FulfilmentType.delivery, OrderStatus.outForDelivery) =>
        OrderStatus.delivered,
      _ => order.status,
    };
    await _client.rpc(
      'update_order_status',
      params: {
        'target_order_id': order.id,
        'next_status': _orderStatusToDatabase(next),
        'ready_at': null,
        'delivery_name': null,
        'delivery_phone': null,
      },
    );
  }

  Future<void> cancelOrder(String orderId) => _client.rpc(
    'cancel_own_order',
    params: {'target_order_id': orderId, 'reason': 'Cancelled by customer'},
  );

  Future<CustomerAddress> updateAddress(CustomerAddress address) async {
    final row = await _client
        .from('addresses')
        .update({
          'label': address.label,
          'recipient_name': address.recipientName,
          'phone': address.phone,
          'line1': address.line1,
          'city': address.city,
          'pincode': address.pincode,
          'instructions': address.instructions,
        })
        .eq('id', address.id)
        .select()
        .single();
    return address.copyWith(
      label: row['label'] as String,
      recipientName: row['recipient_name'] as String,
      phone: row['phone'] as String,
      line1: row['line1'] as String,
      city: row['city'] as String,
      pincode: row['pincode'] as String,
      instructions: row['instructions'] as String? ?? '',
    );
  }

  Future<void> deleteAddress(String addressId) async {
    await _client.from('addresses').delete().eq('id', addressId);
  }

  Future<void> setDefaultAddress(String addressId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Authentication required.');
    await _client
        .from('addresses')
        .update({'is_default': false})
        .eq('user_id', user.id);
    await _client
        .from('addresses')
        .update({'is_default': true})
        .eq('id', addressId);
  }

  CustomerOrder _orderFromRow(Map<String, dynamic> row) {
    final itemRows = (row['order_items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return CustomerOrder(
      id: row['id'] as String,
      reference: 'KOY${row['order_number']}',
      items: itemRows
          .map(
            (item) => OrderItemSnapshot(
              productId: item['product_id'] as String? ?? '',
              name: item['product_name'] as String,
              unit: item['unit'] as String,
              unitPricePaise: item['unit_price_paise'] as int,
              quantity: item['quantity'] as int,
              visualKey: 'grocery',
            ),
          )
          .toList(growable: false),
      fulfilmentType: row['fulfilment_type'] == 'pickup'
          ? FulfilmentType.pickup
          : FulfilmentType.delivery,
      fulfilmentDate: DateTime.parse(row['fulfilment_date'] as String),
      slotLabel: row['slot_label'] as String,
      addressText: row['delivery_address_text'] as String?,
      subtotalPaise: row['subtotal_paise'] as int,
      deliveryChargePaise: row['delivery_charge_paise'] as int,
      discountPaise: row['discount_paise'] as int,
      totalPaise: row['total_paise'] as int,
      paymentMethod: _paymentMethodFromDatabase(
        row['payment_method'] as String,
      ),
      paymentStatus: _paymentStatusFromDatabase(
        row['payment_status'] as String,
      ),
      status: _orderStatusFromDatabase(row['order_status'] as String),
      deliveryInstructions: row['delivery_instructions'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  String _categoryVisual(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('fruit') || normalized.contains('vegetable')) {
      return 'fresh';
    }
    if (normalized.contains('dairy') || normalized.contains('egg')) {
      return 'dairy';
    }
    if (normalized.contains('breakfast') ||
        normalized.contains('ready-to-cook')) {
      return 'breakfast';
    }
    if (normalized.contains('staple')) return 'staples';
    if (normalized.contains('snack') || normalized.contains('sweet')) {
      return 'snacks';
    }
    if (normalized.contains('beverage') || normalized.contains('drink')) {
      return 'beverages';
    }
    if (normalized.contains('personal')) return 'personal';
    if (normalized.contains('baby')) return 'baby';
    if (normalized.contains('home care')) return 'household';
    if (normalized.contains('health')) return 'health';
    if (normalized.contains('pooja')) return 'pooja';
    if (normalized.contains('household')) return 'general';
    return 'grocery';
  }

  String _paymentMethodToDatabase(PaymentMethod value) => switch (value) {
    PaymentMethod.cashOnDelivery => 'cash_on_delivery',
    PaymentMethod.payAtStore => 'pay_at_store',
    PaymentMethod.online => 'online',
  };

  PaymentMethod _paymentMethodFromDatabase(String value) => switch (value) {
    'cash_on_delivery' => PaymentMethod.cashOnDelivery,
    'pay_at_store' => PaymentMethod.payAtStore,
    _ => PaymentMethod.online,
  };

  PaymentStatus _paymentStatusFromDatabase(String value) => switch (value) {
    'paid' => PaymentStatus.paid,
    'failed' => PaymentStatus.failed,
    'cancelled' || 'refunded' => PaymentStatus.cancelled,
    _ => PaymentStatus.pending,
  };

  OrderStatus _orderStatusFromDatabase(String value) => switch (value) {
    'confirmed' => OrderStatus.confirmed,
    'preparing' => OrderStatus.preparing,
    'ready_for_pickup' => OrderStatus.readyForPickup,
    'collected' => OrderStatus.collected,
    'ready_for_dispatch' => OrderStatus.readyForDispatch,
    'out_for_delivery' => OrderStatus.outForDelivery,
    'delivered' => OrderStatus.delivered,
    'cancelled' => OrderStatus.cancelled,
    'rejected' => OrderStatus.rejected,
    _ => OrderStatus.placed,
  };

  String _orderStatusToDatabase(OrderStatus value) => switch (value) {
    OrderStatus.placed => 'placed',
    OrderStatus.confirmed => 'confirmed',
    OrderStatus.preparing => 'preparing',
    OrderStatus.readyForPickup => 'ready_for_pickup',
    OrderStatus.collected => 'collected',
    OrderStatus.readyForDispatch => 'ready_for_dispatch',
    OrderStatus.outForDelivery => 'out_for_delivery',
    OrderStatus.delivered => 'delivered',
    OrderStatus.cancelled => 'cancelled',
    OrderStatus.rejected => 'rejected',
  };

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

extension RemoteStoreHydration on StoreController {
  void hydrateRemoteBundle(RemoteStoreBundle bundle) {
    hydrateFromBackend(
      profile: bundle.profile,
      categories: bundle.categories,
      products: bundle.products,
      addresses: bundle.addresses,
      orders: bundle.orders,
      pickupSlots: bundle.pickupSlots,
      deliverySlots: bundle.deliverySlots,
      isAdmin: bundle.isAdmin,
      serviceablePincodes: bundle.serviceablePincodes,
      minimumOrderPaise: bundle.minimumOrderPaise,
      baseDeliveryChargePaise: bundle.baseDeliveryChargePaise,
      freeDeliveryThresholdPaise: bundle.freeDeliveryThresholdPaise,
      pickupEnabled: bundle.pickupEnabled,
      deliveryEnabled: bundle.deliveryEnabled,
      cashOnDeliveryEnabled: bundle.cashOnDeliveryEnabled,
    );
  }
}
