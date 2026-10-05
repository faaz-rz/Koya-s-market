import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/store/data/store_sync_cache.dart';

List<dynamic> product({int stock = 5}) => [
  'product',
  'category',
  'Atta',
  '',
  '1 kg',
  8000,
  null,
  stock,
  1,
  '',
  'Brand',
  'photos/atta.webp',
  null,
  false,
  true,
  true,
  null,
  null,
  null,
  null,
];
const hash = '00000000000000000000000000000000';
const nextHash = '11111111111111111111111111111111';
Map<String, dynamic> bucket(int id, List rows, {String fingerprint = hash}) => {
  'id': id,
  'hash': fingerprint,
  'rows': rows,
};
Map<String, dynamic> snapshot({bool admin = false}) => {
  'schema': 1,
  'user_id': 'alice',
  'is_admin': admin,
  'catalogue': List.generate(64, (i) => bucket(i, i == 0 ? [product()] : [])),
  'orders': List.generate(
    64,
    (i) => bucket(
      i,
      i == 0
          ? [
              {
                'id': 'private-order',
                'created_at': '2026-09-19',
                'user_id': 'alice',
              },
            ]
          : [],
    ),
  ),
  'metadata_hash': hash,
  'metadata': {
    'profile': {'phone': 'private-phone'},
    'addresses': ['private-address'],
  },
};
Map<String, dynamic> unchanged() => {
  'schema': 1,
  'user_id': 'alice',
  'is_admin': false,
  'catalogue': [],
  'orders': [],
  'metadata_hash': hash,
  'metadata': null,
};

void main() {
  test('cold, unchanged, stock edit and empty deletion replace buckets', () {
    final cache = StoreSyncCache();
    expect(cache.apply(snapshot(), expectedUserId: 'alice'), true);
    expect(cache.products.single['stock_quantity'], 5);
    expect(cache.apply(unchanged(), expectedUserId: 'alice'), false);
    cache.apply({
      ...unchanged(),
      'catalogue': [
        bucket(0, [product(stock: 4)], fingerprint: nextHash),
      ],
    }, expectedUserId: 'alice');
    expect(cache.products.single['stock_quantity'], 4);
    expect((cache.request['known_catalogue'] as Map)['0'], nextHash);
    cache.apply({
      ...unchanged(),
      'catalogue': [bucket(0, [])],
    }, expectedUserId: 'alice');
    expect(cache.products, isEmpty);
    expect(cache.orders, hasLength(1));
  });

  test('public disk cache excludes personal and staff data', () {
    final original = StoreSyncCache()
      ..apply(snapshot(), expectedUserId: 'alice');
    final encoded = original.publicCatalogueJson()!;
    for (final secret in [
      'alice',
      'private-order',
      'private-phone',
      'private-address',
      'metadata',
    ]) {
      expect(encoded, isNot(contains(secret)));
    }
    final restored = StoreSyncCache()..restorePublicCatalogue(encoded);
    expect(restored.products.single['name'], 'Atta');
    expect(restored.request['known_orders'], isEmpty);
    expect(restored.metadata, isNull);
    expect(restored.userId, isNull);
    final staff = StoreSyncCache()
      ..apply(snapshot(admin: true), expectedUserId: 'alice');
    expect(staff.publicCatalogueJson(), isNull);
  });

  test(
    'corrupt, stale, future, incomplete and private disk caches are discarded',
    () {
      final cache = StoreSyncCache()
        ..apply(snapshot(), expectedUserId: 'alice');
      final saved = cache.publicCatalogueJson()!;
      for (final mutate in <void Function(Map)>[
        (d) => d['schema'] = 99,
        (d) => d['saved_at'] = DateTime.now()
            .subtract(const Duration(days: 31))
            .toIso8601String(),
        (d) => d['saved_at'] = DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
        (d) => (d['catalogue'] as Map).remove('63'),
        (d) => d['catalogue']['0']['rows'][0][5] = 'not-a-price',
        (d) => d['catalogue']['0']['rows'][0][16] = 'private staff name',
        (d) => d['catalogue']['0']['rows'][0][14] = false,
      ]) {
        final decoded = jsonDecode(saved) as Map;
        mutate(decoded);
        final restored = StoreSyncCache()
          ..restorePublicCatalogue(jsonEncode(decoded));
        expect(restored.request['known_catalogue'], isEmpty);
      }
      expect((StoreSyncCache()..restorePublicCatalogue('{')).products, isEmpty);
    },
  );

  test(
    'invalid response is atomic and cannot poison matching fingerprints',
    () {
      final cache = StoreSyncCache()
        ..apply(snapshot(), expectedUserId: 'alice');
      final before = jsonEncode(cache.request);
      final invalid = product()..[5] = 'invalid';
      expect(
        () => cache.apply({
          ...unchanged(),
          'catalogue': [
            bucket(1, [product()], fingerprint: nextHash),
            bucket(0, [invalid]),
          ],
        }, expectedUserId: 'alice'),
        throwsFormatException,
      );
      expect(jsonEncode(cache.request), before);
      expect(cache.products, hasLength(1));
    },
  );

  test(
    'rejects partial cold snapshot, duplicate buckets and cross-user reuse',
    () {
      expect(
        () => StoreSyncCache().apply(unchanged(), expectedUserId: 'alice'),
        throwsFormatException,
      );
      final cache = StoreSyncCache()
        ..apply(snapshot(), expectedUserId: 'alice');
      expect(
        () => cache.apply({
          ...unchanged(),
          'catalogue': [bucket(0, []), bucket(0, [])],
        }, expectedUserId: 'alice'),
        throwsFormatException,
      );
      expect(
        () => cache.apply({
          ...unchanged(),
          'user_id': 'bob',
        }, expectedUserId: 'bob'),
        throwsFormatException,
      );
      expect(
        () => cache.apply({
          ...unchanged(),
          'is_admin': true,
        }, expectedUserId: 'alice'),
        throwsFormatException,
      );
      expect(
        () => cache.apply(unchanged(), expectedUserId: 'bob'),
        throwsFormatException,
      );
    },
  );
}
