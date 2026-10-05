import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:koyas_supermarket/core/utils/transaction_request.dart';
import 'package:koyas_supermarket/features/checkout/models/checkout_models.dart';
import 'package:koyas_supermarket/features/store/data/supabase_store_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'store_repository_sync_test.dart' show clientFor, cold, response;

const address = CustomerAddress(
  id: 'new-address',
  label: 'Home',
  recipientName: 'Alice Test',
  phone: '+91 9876543210',
  line1: '12 Test Street',
  city: 'Test City',
  pincode: '678001',
);
const productId = '12345678-1234-4123-8123-123456789012';

void main() {
  test(
    'parallel saves share one address request across repository instances',
    () async {
      final pending = Completer<http.Response>();
      final received = Completer<void>();
      var calls = 0;
      final client = await clientFor((request) async {
        expect(request.url.path, '/rest/v1/rpc/mutate_customer');
        final body = jsonDecode(request.body) as Map;
        expect(body['mutation']['action'], 'save_address');
        expect(body['mutation']['address_id'], isNull);
        expect(body['request_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
        calls++;
        received.complete();
        return pending.future;
      });
      addTearDown(client.dispose);
      final first = SupabaseStoreRepository(client: client).addAddress(address);
      final second = SupabaseStoreRepository(
        client: client,
      ).addAddress(address);
      await received.future;
      expect(calls, 1);
      pending.complete(
        response({
          'id': productId,
          'revision': 0,
          'label': address.label,
          'recipient_name': address.recipientName,
          'phone': address.phone,
          'line1': address.line1,
          'city': address.city,
          'pincode': address.pincode,
          'is_default': true,
        }),
      );
      expect((await first).id, (await second).id);
      expect(calls, 1);
    },
  );
  test(
    'a timed-out stock mutation stops and manual retry reuses its request ID',
    () async {
      final pending = Completer<http.Response>();
      final ids = <String>[];
      final client = await clientFor((request) async {
        ids.add((jsonDecode(request.body) as Map)['request_id'] as String);
        return ids.length <= 3
            ? pending.future
            : response({'stock_quantity': 12});
      });
      addTearDown(client.dispose);
      final repository = SupabaseStoreRepository(
        client: client,
        requestTimeout: const Duration(milliseconds: 5),
      );
      await expectLater(
        repository.adjustProductStock(productId, 2),
        throwsA(isA<TimeoutException>()),
      );
      expect(ids.length, 3);
      expect(await repository.adjustProductStock(productId, 2), 12);
      expect(ids.toSet(), hasLength(1));
      pending.complete(response({'stock_quantity': 12}));
    },
  );
  test(
    'logout while an RPC fails prevents any retry under the next session',
    () async {
      late SupabaseClient client;
      var calls = 0;
      client = await clientFor((request) async {
        calls++;
        SupabaseStoreRepository.clearReadCache(client);
        return http.Response(
          '{"message":"busy","code":"55P03"}',
          409,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.dispose);
      await expectLater(
        SupabaseStoreRepository(
          client: client,
        ).adjustProductStock(productId, 1),
        throwsA(isA<AuthException>()),
      );
      expect(calls, 1);
    },
  );
  test(
    'a late read cannot restore a cleared same-user session cache',
    () async {
      final pending = Completer<http.Response>(), reached = Completer<void>();
      var calls = 0;
      final client = await clientFor((request) async {
        if (++calls == 1) {
          reached.complete();
          return pending.future;
        }
        return response(cold());
      });
      addTearDown(client.dispose);
      final repository = SupabaseStoreRepository(client: client);
      final old = repository.loadStore();
      final rejected = expectLater(old, throwsA(isA<AuthException>()));
      await reached.future;
      SupabaseStoreRepository.clearReadCache(client);
      expect((await repository.loadStore()).profile.id, 'alice');
      pending.complete(response(cold()));
      await rejected;
      expect(calls, 2);
    },
  );
  test('equivalent nested request payloads keep one retry identity', () async {
    final registry = InventoryRequestRegistry(), ids = <String>[];
    await expectLater(
      registry.run(
        userId: 'user',
        request: {
          'a': 1,
          'b': {'x': 2, 'y': 3},
        },
        send: (id) async {
          ids.add(id);
          throw StateError('lost response');
        },
      ),
      throwsStateError,
    );
    await registry.run(
      userId: 'user',
      request: {
        'b': {'y': 3, 'x': 2},
        'a': 1,
      },
      send: (id) async {
        ids.add(id);
        return {};
      },
    );
    expect(ids.toSet(), hasLength(1));
  });
  test(
    'known validation resets a failed checkout but never releases an earlier uncertain key',
    () async {
      final known = CheckoutAttempt<String>();
      await expectLater(
        known.submit('basket', (_, _, _) async {
          throw const TransactionValidationException('Offer expired', 'P0001');
        }),
        throwsA(isA<TransactionValidationException>()),
      );
      expect(known.snapshot, isNull);
      final uncertain = CheckoutAttempt<String>(), ids = <String>[];
      await expectLater(
        uncertain.submit('original', (_, id, _) async {
          ids.add(id);
          throw StateError('response lost');
        }),
        throwsStateError,
      );
      await expectLater(
        uncertain.submit('changed', (_, id, _) async {
          ids.add(id);
          throw const TransactionValidationException('Offer expired', 'P0001');
        }),
        throwsA(isA<TransactionValidationException>()),
      );
      expect(uncertain.snapshot, 'original');
      expect(uncertain.hasUncertainResult, true);
      expect(ids.toSet(), hasLength(1));
    },
  );
}
