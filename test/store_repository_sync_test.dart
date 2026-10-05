import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:koyas_supermarket/features/store/data/supabase_store_repository.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';
import 'store_sync_cache_test.dart' as fixtures;

Map<String, dynamic> cold() => {
  ...fixtures.snapshot(),
  'orders': List.generate(64, (i) => fixtures.bucket(i, [])),
  'metadata': {
    'profile': {'full_name': 'Alice', 'phone': ''},
    'categories': [
      {'id': 'category', 'name': 'Atta'},
    ],
    'addresses': [],
    'slots': [],
    'pincodes': [],
    'offers': [],
    'settings': {
      'minimum_order_paise': 0,
      'delivery_charge_paise': 0,
      'free_delivery_threshold_paise': 0,
      'pickup_enabled': true,
      'delivery_enabled': true,
      'cash_on_delivery_enabled': true,
    },
  },
};
Future<SupabaseClient> clientFor(
  Future<http.Response> Function(http.Request) handler,
) async {
  final client = SupabaseClient(
    'https://store.test',
    'test-public',
    httpClient: MockClient((request) async {
      final result = await handler(request);
      return http.Response.bytes(
        result.bodyBytes,
        result.statusCode,
        request: request,
        headers: result.headers,
      );
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final payload = base64Url.encode(
    utf8.encode(jsonEncode({'exp': 4102444800, 'sub': 'alice'})),
  );
  await client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'test.$payload.test',
      'token_type': 'bearer',
      'user': {
        'id': 'alice',
        'email': 'alice@example.test',
        'aud': 'authenticated',
        'created_at': '2026-09-19T00:00:00Z',
      },
    }),
  );
  return client;
}

http.Response response(Map<String, dynamic> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'checkout RPC times out instead of indefinitely trapping the payment screen',
    () async {
      final responsePending = Completer<http.Response>();
      String? requestedPath;
      final client = await clientFor((request) async {
        requestedPath = request.url.path;
        return responsePending.future;
      });
      addTearDown(client.dispose);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(storeProvider.notifier)..loginDemo();
      controller.addToCart(
        container
            .read(storeProvider)
            .products
            .firstWhere((p) => p.isAvailable)
            .id,
      );
      Object? observedError;
      final result =
          SupabaseStoreRepository(
                client: client,
                requestTimeout: const Duration(milliseconds: 10),
              )
              .placeOrder(
                store: container.read(storeProvider),
                idempotencyKey: 'unchanged-key',
              )
              .then<void>(
                (_) {},
                onError: (Object error, StackTrace _) {
                  observedError = error;
                },
              );
      await result;
      responsePending.complete(
        http.Response(
          '"committed-order"',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect(requestedPath, '/rest/v1/rpc/place_order_v2');
      expect(observedError, isA<TimeoutException>());
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'parallel reads coalesce into one RPC and unchanged refresh reuses bundle',
    () async {
      var calls = 0;
      final pending = Completer<http.Response>(), received = Completer<void>();
      final client = await clientFor((request) async {
        expect(request.url.path, '/rest/v1/rpc/sync_store');
        calls++;
        if (calls == 1) {
          received.complete();
          return pending.future;
        }
        expect((jsonDecode(request.body)['known_catalogue'] as Map).length, 64);
        return response(fixtures.unchanged());
      });
      addTearDown(client.dispose);
      final repository = SupabaseStoreRepository(client: client);
      final first = repository.loadStore(), second = repository.loadStore();
      await received.future;
      expect(calls, 1);
      pending.complete(response(cold()));
      final bundle = await first;
      expect(identical(bundle, await second), true);
      expect(bundle.products.single.stockQuantity, 5);
      expect(identical(bundle, await repository.loadStore()), true);
      expect(calls, 2);
    },
  );

  test(
    'a write during an in-flight sync forces a post-commit snapshot',
    () async {
      var reads = 0;
      final pending = Completer<http.Response>(), received = Completer<void>();
      final client = await clientFor((request) async {
        if (request.url.path.endsWith('admin_mutate_configuration')) {
          return response({'revision': 1});
        }
        reads++;
        if (reads == 1) {
          received.complete();
          return pending.future;
        }
        return response({
          ...fixtures.unchanged(),
          'catalogue': [
            fixtures.bucket(0, [
              fixtures.product(stock: 4),
            ], fingerprint: fixtures.nextHash),
          ],
        });
      });
      addTearDown(client.dispose);
      final repository = SupabaseStoreRepository(client: client);
      final original = repository.loadStore();
      await received.future;
      await repository.updateOrderPricing(
        expectedRevision: 0,
        minimumOrderPaise: 0,
        deliveryChargePaise: 0,
        freeDeliveryThresholdPaise: 0,
      );
      final afterWrite = repository.loadStore();
      pending.complete(response(cold()));
      expect((await original).products.single.stockQuantity, 4);
      expect((await afterWrite).products.single.stockQuantity, 4);
      expect(reads, 2);
    },
  );

  test(
    'failed sync releases in-flight slot and retries without demo data',
    () async {
      var reads = 0;
      final client = await clientFor((request) async {
        if (++reads == 1) {
          return http.Response('{"message":"denied","code":"42501"}', 403);
        }
        return response(cold());
      });
      addTearDown(client.dispose);
      final repository = SupabaseStoreRepository(client: client);
      await expectLater(
        repository.loadStore(),
        throwsA(isA<PostgrestException>()),
      );
      expect((await repository.loadStore()).profile.name, 'Alice');
      expect(reads, 2);
    },
  );
}
