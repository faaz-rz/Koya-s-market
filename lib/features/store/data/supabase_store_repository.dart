import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/usage_policy.dart';
import '../../../core/utils/transaction_request.dart';

import '../../checkout/models/checkout_models.dart';
import '../../offers/models/store_offer.dart';
import '../../orders/models/order.dart';
import '../../products/models/category.dart';
import '../../products/models/product.dart';
import '../../products/models/product_image_upload.dart';
import '../../profile/models/customer_profile.dart';
import '../providers/store_provider.dart';
import 'customer_catalog_categories.dart';
import 'catalogue_cache_storage.dart';
import 'store_sync_cache.dart';

class RemoteStoreBundle {
  const RemoteStoreBundle({
    required this.profile,
    required this.categories,
    required this.products,
    required this.addresses,
    required this.orders,
    required this.offers,
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
    this.loadSequence = 0,
    this.settingsRevision = 0,
  });

  final CustomerProfile profile;
  final List<ProductCategory> categories;
  final List<Product> products;
  final List<CustomerAddress> addresses;
  final List<CustomerOrder> orders;
  final List<StoreOffer> offers;
  final List<FulfilmentSlot> pickupSlots;
  final List<FulfilmentSlot> deliverySlots;
  final bool isAdmin;
  final Set<String> serviceablePincodes;
  final int minimumOrderPaise;
  final int settingsRevision;
  final int baseDeliveryChargePaise;
  final int freeDeliveryThresholdPaise;
  final bool pickupEnabled;
  final bool deliveryEnabled;
  final bool cashOnDeliveryEnabled;
  final int loadSequence;
}

class SupabaseStoreRepository {
  SupabaseStoreRepository({
    SupabaseClient? client,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final Duration requestTimeout;
  static final _inventoryRequests = InventoryRequestRegistry();
  static int _loadSequence = 0;
  static final _sessions = Expando<Map<String, _ReadSession>>();
  static final _generations = Expando<int>();

  static void clearReadCache(SupabaseClient client) {
    _inventoryRequests.clearScope(client.rest.url);
    _generations[client] = (_generations[client] ?? 0) + 1;
    _sessions[client] = null;
  }

  String _requestOwner() {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Authentication required.');
    // Token refresh keeps session_id; a new login gets a different session.
    final token = _client.auth.currentSession?.accessToken;
    final claims = token == null
        ? <String, dynamic>{}
        : jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(token.split('.')[1])),
                ),
              )
              as Map;
    return '${user.id}:${claims['session_id'] ?? ''}:${_generations[_client] ?? 0}';
  }

  void _checkOwner(String owner) {
    if (_requestOwner() != owner) {
      throw const AuthException('Session changed. Sign in and try again.');
    }
  }

  Future<dynamic> _rpc(
    String name,
    Map<String, dynamic> params,
    String owner,
  ) async {
    _checkOwner(owner);
    try {
      final result = await _client
          .rpc(name, params: params)
          .timeout(requestTimeout);
      _checkOwner(owner);
      return result;
    } finally {
      // Also invalidate a read after an uncertain response; the write may have
      // committed. A timeout never authorizes a new purchase or new request ID.
      if (_client.auth.currentUser != null && _requestOwner() == owner) {
        _recordMutation();
      }
    }
  }

  Future<Map<String, dynamic>> _receiptRpc(
    String name,
    Map<String, dynamic> request,
  ) {
    final owner = _requestOwner();
    return _inventoryRequests.run(
      userId: '${_client.rest.url}:$owner',
      request: {'rpc': name, ...request},
      send: (id) async => Map<String, dynamic>.from(
        await _rpc(name, {...request, 'request_id': id}, owner) as Map,
      ),
    );
  }

  Future<void> _retryRpc(String name, Map<String, dynamic> params) async {
    final owner = _requestOwner();
    await retryTransaction(() => _rpc(name, params, owner));
  }

  Future<RemoteStoreBundle> loadStore() {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Authentication required.');
    final sessions = _sessions[_client] ??= {};
    final session = sessions.putIfAbsent(user.id, _ReadSession.new);
    return session.running ??= _loadAfterMutations(
      user,
      session,
    ).whenComplete(() => session.running = null);
  }

  void _recordMutation() {
    final session = _sessions[_client]?[_client.auth.currentUser?.id];
    if (session != null) session.mutationEpoch++;
  }

  Future<RemoteStoreBundle> _loadAfterMutations(
    User user,
    _ReadSession session,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final epoch = session.mutationEpoch;
      final bundle = await _loadStore(user, session);
      // A coalesced read started before a checkout/admin save must not be
      // returned as the post-save refresh. Validate again after that commit.
      if (epoch == session.mutationEpoch) return bundle;
    }
    throw StateError('Store changed repeatedly during refresh. Try again.');
  }

  Future<RemoteStoreBundle> _loadStore(User user, _ReadSession session) async {
    final owner = _requestOwner();
    final sequence = ++_loadSequence;
    if (!session.restored) {
      session.restored = true;
      if (AppEnvironment.supabaseUrl.isNotEmpty) {
        session.cache.restorePublicCatalogue(
          await readCatalogueCache(
            AppEnvironment.supabaseUrl,
          ).timeout(const Duration(seconds: 2), onTimeout: () => null),
        );
      }
    }
    final response = Map<String, dynamic>.from(
      await _client
              .rpc('sync_store', params: session.cache.request)
              .timeout(const Duration(seconds: 15))
          as Map,
    );
    if (_client.auth.currentUser?.id != user.id ||
        _requestOwner() != owner ||
        !identical(_sessions[_client]?[user.id], session)) {
      throw const AuthException('Session changed while refreshing the store.');
    }
    final changed = session.cache.apply(response, expectedUserId: user.id);
    if (!changed && session.bundle != null) return session.bundle!;
    final data = session.cache.metadata!;
    final isAdmin = session.cache.isAdmin;
    final profileRow = data['profile'] as Map<String, dynamic>?;
    List<Map<String, dynamic>> rows(String key) => (data[key] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final categoryRows = rows('categories');
    final reuseProducts =
        (response['catalogue'] as List).isEmpty &&
        response['metadata'] == null &&
        session.bundle != null;
    final productRows = reuseProducts
        ? <Map<String, dynamic>>[]
        : session.cache.products;
    productRows.sort((a, b) {
      final availability = (b['available'] == true ? 1 : 0).compareTo(
        a['available'] == true ? 1 : 0,
      );
      return availability != 0
          ? availability
          : (a['name'] as String).compareTo(b['name'] as String);
    });
    final addressRows = rows('addresses');
    final slotRows = rows('slots');
    final settingsRow = data['settings'] as Map<String, dynamic>;
    final pincodeRows = rows('pincodes');
    final orderRows = session.cache.orders;
    final offerRows = rows('offers');
    if ((response['catalogue'] as List).isNotEmpty &&
        AppEnvironment.supabaseUrl.isNotEmpty) {
      final cache = session.cache.publicCatalogueJson();
      if (cache != null) {
        await writeCatalogueCache(
          AppEnvironment.supabaseUrl,
          cache,
        ).timeout(const Duration(seconds: 2), onTimeout: () {});
      }
    }

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
    final products = reuseProducts
        ? session.bundle!.products
        : productRows
              .where((row) => categoryVisuals.containsKey(row['category_id']))
              .map((row) {
                final imagePath = row['image_path'] as String?;
                return Product(
                  id: row['id'] as String,
                  categoryId: row['category_id'] as String,
                  name: row['name'] as String,
                  description: row['description'] as String? ?? '',
                  unit: row['unit'] as String,
                  pricePaise: row['price_paise'] as int,
                  discountPricePaise: row['discount_price_paise'] as int?,
                  stockQuantity: row['stock_quantity'] as int,
                  revision: (row['revision'] as num?)?.toInt() ?? 0,
                  visualKey: categoryVisuals[row['category_id']] ?? 'grocery',
                  subcategory: row['subcategory'] as String? ?? '',
                  brand: row['brand'] as String? ?? '',
                  billingName: row['source_product_name'] as String? ?? '',
                  printName: row['source_print_name'] as String? ?? '',
                  itemCode: row['source_item_code'] as String? ?? '',
                  barcode: row['barcode'] as String? ?? '',
                  // Production clients only fetch product media from the controlled
                  // Supabase bucket. Imported third-party URLs would disclose each
                  // customer's IP address and user agent to unrelated hosts.
                  imageUrl: imagePath == null || imagePath.isEmpty
                      ? null
                      : _client.storage
                            .from('product-images')
                            .getPublicUrl(imagePath),
                  imagePath: imagePath ?? '',
                  imageAttribution: row['image_attribution'] as String? ?? '',
                  featured: row['featured'] as bool? ?? false,
                  active: row['active'] as bool? ?? true,
                  available: row['available'] as bool? ?? true,
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
            revision: (row['revision'] as num?)?.toInt() ?? 0,
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
    final offers = offerRows
        .map(
          (row) => StoreOffer(
            id: row['id'] as String,
            revision: (row['revision'] as num?)?.toInt() ?? 0,
            code: row['code'] as String,
            title: row['title'] as String,
            description: row['description'] as String? ?? '',
            minimumSubtotalPaise: row['minimum_subtotal_paise'] as int,
            discountType: switch (row['discount_type'] as String?) {
              'flat' => OfferDiscountType.flat,
              'percentage' => OfferDiscountType.percentage,
              _ => null,
            },
            discountValue: row['discount_value'] as int? ?? 0,
            maximumDiscountPaise: row['maximum_discount_paise'] as int?,
            freeProductId: row['free_product_id'] as String?,
            freeQuantity: row['free_quantity'] as int? ?? 1,
            requiredFulfilment: switch (row['required_fulfilment'] as String?) {
              'pickup' => FulfilmentType.pickup,
              'delivery' => FulfilmentType.delivery,
              _ => null,
            },
            startsAt: row['starts_at'] == null
                ? null
                : DateTime.parse(row['starts_at'] as String).toLocal(),
            endsAt: row['ends_at'] == null
                ? null
                : DateTime.parse(row['ends_at'] as String).toLocal(),
            totalRedemptionLimit: row['total_redemption_limit'] as int?,
            perCustomerLimit: row['per_customer_limit'] as int? ?? 1,
            active: row['active'] as bool? ?? false,
          ),
        )
        .toList(growable: false);
    final metadataName = user.userMetadata?['full_name'] as String?;
    final bundle = RemoteStoreBundle(
      loadSequence: sequence,
      profile: CustomerProfile(
        id: user.id,
        revision: (profileRow?['revision'] as num?)?.toInt() ?? 0,
        name: (profileRow?['full_name'] as String?)?.trim().isNotEmpty == true
            ? profileRow!['full_name'] as String
            : metadataName?.trim().isNotEmpty == true
            ? metadataName!
            : 'Koya Stores customer',
        email: user.email ?? '',
        phone: profileRow?['phone'] as String? ?? user.phone ?? '',
      ),
      categories: categories,
      products: products,
      addresses: addresses,
      orders: orders,
      offers: offers,
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
      settingsRevision: (settingsRow['revision'] as num?)?.toInt() ?? 0,
      minimumOrderPaise: settingsRow['minimum_order_paise'] as int,
      baseDeliveryChargePaise: settingsRow['delivery_charge_paise'] as int,
      freeDeliveryThresholdPaise:
          settingsRow['free_delivery_threshold_paise'] as int,
      pickupEnabled: settingsRow['pickup_enabled'] as bool,
      deliveryEnabled: settingsRow['delivery_enabled'] as bool,
      cashOnDeliveryEnabled: settingsRow['cash_on_delivery_enabled'] as bool,
    );
    session.bundle = bundle;
    return bundle;
  }

  Future<String> placeOrder({
    required StoreState store,
    required String idempotencyKey,
    DateTime? checkoutStartedAt,
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
        ? checkoutStartedAt ?? DateTime.now()
        : store.selectedDate;
    try {
      final response = await _rpc('place_order_v2', {
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
        'requested_offer_code': store.selectedOfferCode,
      }, _requestOwner());
      return response as String;
    } on PostgrestException catch (error) {
      // Keep rollback/conflict codes for the checkout coordinator. Business
      // errors are rendered safely by the payment screen after it resets the
      // failed attempt; a conflicting/uncertain attempt must keep its key.
      if (error.code == 'PT409' ||
          const {
            '40001',
            '40P01',
            '55P03',
            '57014',
            '502',
            '503',
            '504',
          }.contains(error.code)) {
        rethrow;
      }
      final message = error.message.toLowerCase();
      if (message.contains('offer code was not found')) {
        throw TransactionValidationException(
          'Offer code was not found.',
          error.code,
        );
      }
      if (message.contains('offer is not active')) {
        throw TransactionValidationException(
          'This offer is no longer active.',
          error.code,
        );
      }
      if (message.contains('minimum basket')) {
        throw TransactionValidationException(
          'Your basket no longer meets this offer’s minimum.',
          error.code,
        );
      }
      if (message.contains('free product')) {
        throw TransactionValidationException(
          'The free product is currently unavailable.',
          error.code,
        );
      }
      if (message.contains('already used') ||
          message.contains('redemption limit')) {
        throw TransactionValidationException(
          'This offer has reached its usage limit.',
          error.code,
        );
      }
      if (message.contains('fulfilment method')) {
        throw TransactionValidationException(
          'This offer is not valid for the selected fulfilment method.',
          error.code,
        );
      }
      rethrow;
    }
  }

  Map<String, dynamic> _addressMutation(CustomerAddress address) => {
    'action': 'save_address',
    'address_id': _isUuid(address.id) ? address.id : null,
    'label': address.label,
    'recipient_name': address.recipientName,
    'phone': address.phone,
    'line1': address.line1,
    'city': address.city,
    'pincode': address.pincode,
    'instructions': address.instructions,
    'is_default': address.isDefault,
  };

  CustomerAddress _addressFromRow(Map<String, dynamic> row) => CustomerAddress(
    id: row['id'] as String,
    revision: (row['revision'] as num).toInt(),
    label: row['label'] as String,
    recipientName: row['recipient_name'] as String,
    phone: row['phone'] as String,
    line1: row['line1'] as String,
    city: row['city'] as String,
    pincode: row['pincode'] as String,
    instructions: row['instructions'] as String? ?? '',
    isDefault: row['is_default'] as bool? ?? false,
  );

  Future<CustomerAddress> addAddress(CustomerAddress address) async =>
      _addressFromRow(
        await _receiptRpc('mutate_customer', {
          'expected_revision': null,
          'mutation': {..._addressMutation(address), 'address_id': null},
        }),
      );

  Future<CustomerProfile> updateProfile(CustomerProfile profile) async {
    if (profile.id != _client.auth.currentUser?.id) {
      throw const AuthException('Session changed. Sign in and try again.');
    }
    final row = await _receiptRpc('mutate_customer', {
      'expected_revision': profile.revision,
      'mutation': {
        'action': 'save_profile',
        'full_name': profile.name,
        'phone': profile.phone,
      },
    });
    return profile.copyWith(
      revision: (row['revision'] as num).toInt(),
      name: row['full_name'] as String,
      phone: row['phone'] as String? ?? '',
    );
  }

  Future<void> saveProduct(
    Product product, {
    ProductImageUpload? image,
    bool removeImage = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Authentication required.');

    final mutation = <String, dynamic>{
      'action': 'save',
      'target_product_id': _isUuid(product.id) ? product.id : null,
      'product_category_id': product.categoryId,
      'product_name': product.name,
      'product_description': product.description,
      'product_unit': product.unit,
      'product_price_paise': product.pricePaise,
      'product_discount_price_paise': product.discountPricePaise,
      'product_stock_quantity': product.stockQuantity,
      'product_featured': product.featured,
      'product_active': product.active,
      'product_available': product.active && product.available,
      'product_subcategory': product.subcategory,
      'product_brand': product.brand,
      'product_billing_name': product.billingName,
      'product_print_name': product.printName,
      'product_item_code': product.itemCode,
      'product_barcode': product.barcode,
      'remove_product_image': removeImage,
    };
    if (image != null &&
        image.bytes.length > UsagePolicy.optimizedImageMaxBytes) {
      throw const FormatException(
        'Optimise the product image to 150 KB or less before uploading.',
      );
    }
    final owner = _requestOwner();
    await _inventoryRequests.run(
      userId: '${_client.rest.url}:$owner',
      // Image bytes are part of the LOCAL retry identity, never the RPC body.
      // This keeps the upload path and mutation ID stable after a lost response.
      request: {
        'expected_revision': product.revision,
        'mutation': mutation,
        'image': image == null ? null : base64Encode(image.bytes),
      },
      send: (id) async {
        _checkOwner(owner);
        final uploadedPath = image == null
            ? null
            : 'products/${user.id}/$id.${image.extension}';
        if (image != null) {
          try {
            await _client.storage
                .from('product-images')
                .uploadBinary(
                  uploadedPath!,
                  image.bytes,
                  fileOptions: FileOptions(
                    cacheControl: '31536000',
                    contentType: image.contentType,
                  ),
                )
                .timeout(requestTimeout);
            _checkOwner(owner);
          } on StorageException catch (error) {
            // Only this immutable request can have written this random path.
            // A retry must not replace it or generate a different RPC payload.
            if (error.statusCode != '409' && error.error != 'Duplicate') {
              rethrow;
            }
          }
        }
        return Map<String, dynamic>.from(
          await _rpc('admin_mutate_product', {
                'request_id': id,
                'expected_revision': product.revision,
                'mutation': {...mutation, 'product_image_path': uploadedPath},
              }, owner)
              as Map,
        );
      },
    );
    _recordMutation();
    // Do not delete storage objects from the client: an uncertain save or a
    // concurrent editor may still reference them. Garbage collection must be
    // a separate server-side, reference-aware maintenance operation.
  }

  Future<void> updateOrderPricing({
    required int minimumOrderPaise,
    required int deliveryChargePaise,
    required int freeDeliveryThresholdPaise,
    required int expectedRevision,
  }) async {
    await _receiptRpc('admin_mutate_configuration', {
      'expected_revision': expectedRevision,
      'mutation': {
        'action': 'pricing',
        'requested_minimum_order_paise': minimumOrderPaise,
        'requested_delivery_charge_paise': deliveryChargePaise,
        'requested_free_delivery_threshold_paise': freeDeliveryThresholdPaise,
      },
    });
    _recordMutation();
  }

  Future<void> saveOffer(StoreOffer offer) async {
    await _receiptRpc('admin_mutate_configuration', {
      'expected_revision': offer.revision,
      'mutation': {
        'action': 'offer',
        'target_offer_id': _isUuid(offer.id) ? offer.id : null,
        'requested_code': offer.code,
        'requested_title': offer.title,
        'requested_description': offer.description,
        'requested_minimum_subtotal_paise': offer.minimumSubtotalPaise,
        'requested_discount_type': switch (offer.discountType) {
          OfferDiscountType.flat => 'flat',
          OfferDiscountType.percentage => 'percentage',
          null => null,
        },
        'requested_discount_value': offer.hasDiscount ? offer.discountValue : 0,
        'requested_maximum_discount_paise': offer.maximumDiscountPaise,
        'requested_free_product_id': offer.freeProductId,
        'requested_free_quantity': offer.freeQuantity,
        'requested_fulfilment': offer.requiredFulfilment?.name,
        'requested_starts_at': offer.startsAt?.toUtc().toIso8601String(),
        'requested_ends_at': offer.endsAt?.toUtc().toIso8601String(),
        'requested_total_redemption_limit': offer.totalRedemptionLimit,
        'requested_per_customer_limit': offer.perCustomerLimit,
        'requested_active': offer.active,
      },
    });
    _recordMutation();
  }

  /// Sets the client's counted on-hand quantity without overwriting price,
  /// name, or other product fields.
  Future<int> setProductStock(
    String productId,
    int quantity, {
    required int expectedRevision,
  }) async {
    if (!_isUuid(productId)) {
      throw ArgumentError.value(productId, 'productId', 'Expected a UUID');
    }
    final result = await _mutateProduct(
      expectedRevision: expectedRevision,
      mutation: {
        'action': 'set_stock',
        'target_product_id': productId,
        'requested_stock': quantity,
      },
    );
    return (result['stock_quantity'] as num).toInt();
  }

  /// Applies quick +/- stock controls atomically so a simultaneous order does
  /// not get overwritten by an admin page holding an older quantity.
  Future<int> adjustProductStock(String productId, int delta) async {
    if (!_isUuid(productId)) {
      throw ArgumentError.value(productId, 'productId', 'Expected a UUID');
    }
    final result = await _mutateProduct(
      mutation: {
        'action': 'adjust_stock',
        'target_product_id': productId,
        'stock_delta': delta,
      },
    );
    return (result['stock_quantity'] as num).toInt();
  }

  Future<Map<String, dynamic>> _mutateProduct({
    required Map<String, dynamic> mutation,
    int? expectedRevision,
  }) async {
    final result = await _receiptRpc('admin_mutate_product', {
      'expected_revision': expectedRevision,
      'mutation': mutation,
    });
    return result;
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
    await _retryRpc('update_order_status', {
      'target_order_id': order.id,
      'next_status': _orderStatusToDatabase(next),
      'ready_at': null,
      'delivery_name': null,
      'delivery_phone': null,
    });
  }

  Future<void> rejectOrder(String orderId) =>
      _updateAdminOrderStatus(orderId, OrderStatus.rejected);

  Future<void> cancelOrderByAdmin(String orderId) =>
      _updateAdminOrderStatus(orderId, OrderStatus.cancelled);

  Future<void> _updateAdminOrderStatus(
    String orderId,
    OrderStatus status,
  ) async {
    await _retryRpc('update_order_status', {
      'target_order_id': orderId,
      'next_status': _orderStatusToDatabase(status),
      'ready_at': null,
      'delivery_name': null,
      'delivery_phone': null,
    });
  }

  Future<void> markOrderPaid(String orderId) async {
    await _retryRpc('admin_mark_order_paid', {'target_order_id': orderId});
  }

  Future<void> cancelOrder(String orderId) async {
    await _retryRpc('cancel_own_order', {
      'target_order_id': orderId,
      'reason': 'Cancelled by customer',
    });
  }

  Future<CustomerAddress> updateAddress(CustomerAddress address) async =>
      _addressFromRow(
        await _receiptRpc('mutate_customer', {
          'expected_revision': address.revision,
          'mutation': _addressMutation(address),
        }),
      );

  Future<void> deleteAddress(
    String addressId, {
    required int expectedRevision,
  }) async {
    await _receiptRpc('mutate_customer', {
      'expected_revision': expectedRevision,
      'mutation': {'action': 'delete_address', 'address_id': addressId},
    });
  }

  Future<CustomerAddress> setDefaultAddress(
    String addressId, {
    required int expectedRevision,
  }) async => _addressFromRow(
    await _receiptRpc('mutate_customer', {
      'expected_revision': expectedRevision,
      'mutation': {'action': 'default_address', 'address_id': addressId},
    }),
  );

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
              isFreeOfferItem: item['is_free_offer_item'] as bool? ?? false,
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
      customerName: row['customer_name_snapshot'] as String? ?? '',
      customerPhone: row['customer_phone_snapshot'] as String? ?? '',
      deliveryRecipientName:
          row['delivery_recipient_name_snapshot'] as String? ?? '',
      deliveryRecipientPhone:
          row['delivery_recipient_phone_snapshot'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      paidAt: row['paid_at'] == null
          ? null
          : DateTime.parse(row['paid_at'] as String).toLocal(),
      offerCode: row['applied_offer_code'] as String?,
      offerTitle: row['applied_offer_title'] as String?,
      offerDiscountPaise: row['offer_discount_paise'] as int? ?? 0,
    );
  }

  String _categoryVisual(String name) {
    final clientVisual = CustomerCatalogCategories.visualForName(name);
    if (clientVisual != null) return clientVisual;
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

class _ReadSession {
  final cache = StoreSyncCache();
  bool restored = false;
  int mutationEpoch = 0;
  RemoteStoreBundle? bundle;
  Future<RemoteStoreBundle>? running;
}

extension RemoteStoreHydration on StoreController {
  void hydrateRemoteBundle(RemoteStoreBundle bundle) {
    hydrateFromBackend(
      loadSequence: bundle.loadSequence,
      profile: bundle.profile,
      categories: bundle.categories,
      products: bundle.products,
      addresses: bundle.addresses,
      orders: bundle.orders,
      offers: bundle.offers,
      pickupSlots: bundle.pickupSlots,
      deliverySlots: bundle.deliverySlots,
      isAdmin: bundle.isAdmin,
      serviceablePincodes: bundle.serviceablePincodes,
      minimumOrderPaise: bundle.minimumOrderPaise,
      settingsRevision: bundle.settingsRevision,
      baseDeliveryChargePaise: bundle.baseDeliveryChargePaise,
      freeDeliveryThresholdPaise: bundle.freeDeliveryThresholdPaise,
      pickupEnabled: bundle.pickupEnabled,
      deliveryEnabled: bundle.deliveryEnabled,
      cashOnDeliveryEnabled: bundle.cashOnDeliveryEnabled,
    );
  }

  /// Owns the refresh independently of the payment route, which is disposed as
  /// soon as confirmation opens. Never hydrate a later login or checkout.
  Future<void> refreshConfirmedCheckout({
    required String orderId,
    required String? customerId,
    required Future<RemoteStoreBundle> Function() load,
  }) async {
    if (!ownsConfirmedCheckout(orderId, customerId)) return;
    try {
      final bundle = await load().timeout(const Duration(seconds: 20));
      if (ownsConfirmedCheckout(orderId, customerId) &&
          bundle.profile.id == customerId) {
        hydrateRemoteBundle(bundle);
      }
    } catch (_) {
      // Checkout committed. Confirmation retains the order ID and Orders can
      // retry loading details; never repeat the purchase because of this read.
    }
  }
}
