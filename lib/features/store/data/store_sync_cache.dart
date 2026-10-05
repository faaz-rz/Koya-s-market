import 'dart:convert';

/// Schema 1 must match sync_store's compact product rows. Staff-only billing
/// fields are null for customers, and admin catalogues are never persisted.
const catalogueColumns = [
  'id',
  'category_id',
  'name',
  'description',
  'unit',
  'price_paise',
  'discount_price_paise',
  'stock_quantity',
  'revision',
  'subcategory',
  'brand',
  'image_path',
  'image_attribution',
  'featured',
  'active',
  'available',
  'source_product_name',
  'source_print_name',
  'source_item_code',
  'barcode',
];

bool _validProductRow(dynamic row) {
  if (row is! List || row.length != catalogueColumns.length) return false;
  for (final index in [0, 1, 2, 4]) {
    if (row[index] is! String) return false;
  }
  for (final index in [5, 7, 8]) {
    if (row[index] is! int) return false;
  }
  if (row[6] != null && row[6] is! int) return false;
  for (final index in [3, 9, 10, 11, 12, 16, 17, 18, 19]) {
    if (row[index] != null && row[index] is! String) return false;
  }
  return [13, 14, 15].every((index) => row[index] is bool);
}

class StoreSyncCache {
  Map<String, dynamic> _catalogue = {};
  Map<String, dynamic> _orders = {};
  Map<String, dynamic>? metadata;
  String? metadataHash;
  bool isAdmin = false;
  String? userId;

  Map<String, dynamic> get request => {
    'known_catalogue': {
      for (final e in _catalogue.entries) e.key: e.value['hash'],
    },
    'known_orders': {for (final e in _orders.entries) e.key: e.value['hash']},
    'known_metadata': metadataHash,
  };

  /// Apply a complete response atomically. A changed bucket replaces the old
  /// bucket, including empty buckets (deleted/archived rows disappear).
  bool apply(Map<String, dynamic> response, {required String expectedUserId}) {
    if (response['schema'] != 1 ||
        response['user_id'] != expectedUserId ||
        response['is_admin'] is! bool ||
        (userId != null && userId != expectedUserId) ||
        response['metadata_hash'] is! String ||
        !RegExp(
          r'^[0-9a-f]{32}$',
        ).hasMatch(response['metadata_hash'] as String)) {
      throw const FormatException('Invalid store sync scope');
    }
    final catalogueChanges = response['catalogue'] as List;
    final orderChanges = response['orders'] as List;
    if (userId != null &&
        isAdmin != response['is_admin'] &&
        (catalogueChanges.length != 64 ||
            orderChanges.length != 64 ||
            response['metadata'] == null)) {
      throw const FormatException('Incomplete role transition');
    }
    final nextCatalogue = {..._catalogue};
    final nextOrders = {..._orders};
    void merge(List changes, Map<String, dynamic> target, bool catalogue) {
      final seen = <int>{};
      for (final raw in changes) {
        final part = Map<String, dynamic>.from(raw as Map);
        final id = part['id'];
        if (id is! int ||
            id < 0 ||
            id > 63 ||
            part['hash'] is! String ||
            !RegExp(r'^[0-9a-f]{32}$').hasMatch(part['hash'] as String) ||
            part['rows'] is! List ||
            !seen.add(id)) {
          throw const FormatException('Invalid sync bucket');
        }
        for (final row in part['rows'] as List) {
          if (catalogue
              ? !_validProductRow(row) ||
                    (response['is_admin'] == false &&
                        (row[14] != true ||
                            (row as List)
                                .skip(16)
                                .any((field) => field != null)))
              : row is! Map ||
                    row['id'] is! String ||
                    row['created_at'] is! String) {
            throw const FormatException('Invalid sync row');
          }
        }
        target['$id'] = part;
      }
    }

    merge(catalogueChanges, nextCatalogue, true);
    merge(orderChanges, nextOrders, false);
    final nextMetadata = response['metadata'] == null
        ? metadata
        : Map<String, dynamic>.from(response['metadata'] as Map);
    if (nextCatalogue.length != 64 ||
        nextOrders.length != 64 ||
        nextMetadata == null) {
      throw const FormatException('Incomplete store sync');
    }
    _catalogue = nextCatalogue;
    _orders = nextOrders;
    metadata = nextMetadata;
    metadataHash = response['metadata_hash'] as String;
    isAdmin = response['is_admin'] as bool;
    userId = expectedUserId;
    return catalogueChanges.isNotEmpty ||
        orderChanges.isNotEmpty ||
        response['metadata'] != null;
  }

  List<Map<String, dynamic>> get products => [
    for (final part in _catalogue.values)
      for (final row in part['rows'] as List)
        {
          for (var i = 0; i < catalogueColumns.length; i++)
            catalogueColumns[i]: row[i],
        },
  ];

  List<Map<String, dynamic>> get orders =>
      [
        for (final part in _orders.values)
          for (final row in part['rows'] as List)
            Map<String, dynamic>.from(row as Map),
      ]..sort(
        (a, b) =>
            (b['created_at'] as String).compareTo(a['created_at'] as String),
      );

  String? publicCatalogueJson() => isAdmin || _catalogue.length != 64
      ? null
      : jsonEncode({
          'schema': 1,
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'catalogue': _catalogue,
        });

  void restorePublicCatalogue(String? data) {
    if (data == null || data.length > 2 * 1024 * 1024) return;
    try {
      final decoded = jsonDecode(data) as Map;
      if (decoded['schema'] != 1) return;
      final saved = DateTime.parse(decoded['saved_at'] as String);
      final age = DateTime.now().toUtc().difference(saved);
      if (age > const Duration(days: 30) || age < const Duration(minutes: -5)) {
        return;
      }
      final catalogue = Map<String, dynamic>.from(decoded['catalogue'] as Map);
      if (catalogue.length != 64) return;
      for (var id = 0; id < 64; id++) {
        final part = catalogue['$id'] as Map;
        if (part['id'] != id ||
            !RegExp(r'^[0-9a-f]{32}$').hasMatch(part['hash'] as String)) {
          return;
        }
        for (final row in part['rows'] as List) {
          if (!_validProductRow(row) ||
              row[14] != true ||
              (row as List).skip(16).any((field) => field != null)) {
            return;
          }
        }
      }
      _catalogue = catalogue;
    } catch (_) {
      // Incomplete/corrupt caches trigger a fresh sync. Never fall back to demo.
    }
  }
}
