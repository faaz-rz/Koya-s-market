import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/core/utils/transaction_request.dart';
import 'package:koyas_supermarket/features/checkout/models/checkout_models.dart';
import 'package:koyas_supermarket/features/orders/screens/order_confirmation_screen.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';
import 'package:koyas_supermarket/features/store/data/supabase_store_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

RemoteStoreBundle checkoutBundle(StoreState original) => RemoteStoreBundle(
  profile: original.profile!,
  categories: original.categories,
  products: original.products,
  addresses: original.addresses,
  orders: original.orders,
  offers: original.offers,
  pickupSlots: original.pickupSlots,
  deliverySlots: original.deliverySlots,
  isAdmin: false,
  serviceablePincodes: original.serviceablePincodes,
  minimumOrderPaise: 12345,
  baseDeliveryChargePaise: original.baseDeliveryChargePaise,
  freeDeliveryThresholdPaise: original.freeDeliveryThresholdPaise,
  pickupEnabled: true,
  deliveryEnabled: true,
  cashOnDeliveryEnabled: true,
);

void main() {
  for (final scenario in [
    'success',
    'failure',
    'logout',
    'new-checkout',
    'disposed',
  ]) {
    test('background confirmation refresh is safe after $scenario', () async {
      final container = ProviderContainer();
      final controller = container.read(storeProvider.notifier)..loginDemo();
      final original = container.read(storeProvider),
          response = Completer<RemoteStoreBundle>();
      controller.finishRemoteCheckout(
        'confirmed',
        customerId: original.profile!.id,
      );
      var completed = false;
      final refresh = controller
          .refreshConfirmedCheckout(
            orderId: 'confirmed',
            customerId: original.profile!.id,
            load: () => response.future,
          )
          .whenComplete(() => completed = true);
      expect(container.read(storeProvider).lastOrderId, 'confirmed');
      expect(completed, false); // Confirmation state is already available.
      if (scenario == 'logout') controller.logout();
      if (scenario == 'new-checkout') {
        controller.finishRemoteCheckout(
          'new-order',
          customerId: original.profile!.id,
        );
      }
      if (scenario == 'disposed') container.dispose();
      if (scenario == 'failure') {
        response.completeError(StateError('offline'));
      } else {
        response.complete(checkoutBundle(original));
      }
      await refresh;
      if (scenario != 'disposed') {
        expect(
          container.read(storeProvider).minimumOrderPaise,
          scenario == 'success' ? 12345 : original.minimumOrderPaise,
        );
        if (scenario == 'new-checkout') {
          expect(container.read(storeProvider).lastOrderId, 'new-order');
        }
        if (scenario == 'logout') {
          expect(container.read(storeProvider).isAuthenticated, false);
        }
        container.dispose();
      }
    });
  }

  testWidgets(
    'timed-out confirmation refresh keeps success and ignores late responses',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(storeProvider.notifier)..loginDemo();
      final original = container.read(storeProvider),
          pending = Completer<RemoteStoreBundle>();
      controller.finishRemoteCheckout(
        'confirmed',
        customerId: original.profile!.id,
      );
      final refreshing = controller.refreshConfirmedCheckout(
        orderId: 'confirmed',
        customerId: original.profile!.id,
        load: () => pending.future,
      );
      await tester.pump(const Duration(seconds: 21));
      await refreshing;
      expect(container.read(storeProvider).lastOrderId, 'confirmed');
      pending.complete(checkoutBundle(original));
      await tester.pump();
      expect(
        container.read(storeProvider).minimumOrderPaise,
        original.minimumOrderPaise,
      );
    },
  );

  test(
    'a later permission failure cannot release an uncertain inventory ID',
    () async {
      final registry = InventoryRequestRegistry();
      const request = {'action': 'adjust_stock', 'stock_delta': 1};
      final ids = <String>[];
      for (final error in [
        StateError('lost response'),
        const PostgrestException(message: 'MFA expired', code: '42501'),
      ]) {
        await expectLater(
          registry.run(
            userId: 'admin',
            request: request,
            send: (id) async {
              ids.add(id);
              throw error;
            },
          ),
          throwsA(same(error)),
        );
      }
      await registry.run(
        userId: 'admin',
        request: request,
        send: (id) async {
          ids.add(id);
          return {};
        },
      );
      expect(ids.toSet(), hasLength(1));
    },
  );

  test(
    'a later permission failure cannot release an uncertain checkout key',
    () async {
      final attempt = CheckoutAttempt<String>(), ids = <String>[];
      for (final error in [
        StateError('lost response'),
        const PostgrestException(message: 'Session expired', code: '42501'),
      ]) {
        await expectLater(
          attempt.submit('original', (_, id, _) async {
            ids.add(id);
            throw error;
          }),
          throwsA(same(error)),
        );
      }
      await attempt.submit('changed', (snapshot, id, _) async {
        ids.add(id);
        expect(snapshot, 'original');
        return 'committed-order';
      });
      expect(ids.toSet(), hasLength(1));
    },
  );

  test('transaction IDs are distinct UUID v4 values', () {
    final ids = List.generate(100, (_) => newTransactionId());
    expect(ids.toSet(), hasLength(100));
    for (final id in ids) {
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    }
  });

  test('transient lock failures retry with bounded backoff', () async {
    var calls = 0;
    final waits = <Duration>[];
    final result = await retryTransaction(
      () async {
        if (++calls < 3) {
          throw const PostgrestException(message: 'busy', code: '55P03');
        }
        return 'saved';
      },
      wait: (delay) async {
        waits.add(delay);
      },
    );
    expect(result, 'saved');
    expect(calls, 3);
    expect(waits.map((d) => d.inMilliseconds), [150, 300]);
  });

  test(
    'exhausted retries stop and business failures never auto-retry',
    () async {
      for (final code in ['40P01', 'PT409', 'P0001']) {
        var calls = 0;
        await expectLater(
          retryTransaction(() async {
            calls++;
            throw PostgrestException(message: 'test', code: code);
          }, wait: (_) async {}),
          throwsA(isA<PostgrestException>()),
        );
        expect(calls, code == '40P01' ? 3 : 1);
      }
    },
  );

  test(
    'inventory double-clicks share one request and successful later edits get a new ID',
    () async {
      final registry = InventoryRequestRegistry(),
          pending = Completer<Map<String, dynamic>>();
      final ids = <String>[];
      Future<Map<String, dynamic>> send(String id) {
        ids.add(id);
        return pending.future;
      }

      const request = {'action': 'adjust_stock', 'stock_delta': 1};
      final first = registry.run(userId: 'admin', request: request, send: send);
      final second = registry.run(
        userId: 'admin',
        request: request,
        send: send,
      );
      expect(identical(first, second), isTrue);
      expect(ids, hasLength(1));
      pending.complete({'stock_quantity': 3});
      await Future.wait([first, second]);
      await registry.run(
        userId: 'admin',
        request: request,
        send: (id) async {
          ids.add(id);
          return {};
        },
      );
      expect(ids.toSet(), hasLength(2));
    },
  );

  test(
    'an ambiguous inventory response retains its ID but isolates other admins',
    () async {
      final registry = InventoryRequestRegistry(), ids = <String>[];
      const request = {'action': 'adjust_stock', 'stock_delta': 1};
      await expectLater(
        registry.run(
          userId: 'admin-a',
          request: request,
          send: (id) async {
            ids.add(id);
            throw StateError('connection dropped');
          },
        ),
        throwsStateError,
      );
      await registry.run(
        userId: 'admin-b',
        request: request,
        send: (id) async {
          ids.add(id);
          return {};
        },
      );
      await registry.run(
        userId: 'admin-a',
        request: request,
        send: (id) async {
          ids.add(id);
          return {};
        },
      );
      expect(ids[0], ids[2]);
      expect(ids[0], isNot(ids[1]));
    },
  );

  test(
    'checkout retries preserve original basket, date and key across screen recreation',
    () async {
      final checkout = CheckoutAttempt<String>(),
          ids = <String>[],
          dates = <DateTime>[];
      await expectLater(
        checkout.submit('original', (snapshot, key, date) async {
          expect(snapshot, 'original');
          ids.add(key);
          dates.add(date);
          throw StateError('lost HTTP response');
        }),
        throwsStateError,
      );
      final order = await checkout.submit('changed basket', (
        snapshot,
        key,
        date,
      ) async {
        expect(snapshot, 'original');
        ids.add(key);
        dates.add(date);
        return 'order-id';
      });
      expect(order, 'order-id');
      expect(ids.toSet(), hasLength(1));
      expect(dates.toSet(), hasLength(1));
      expect(
        await checkout.submit(
          'anything',
          (_, _, _) async => fail('already confirmed'),
        ),
        'order-id',
      );
    },
  );

  test('two checkout screens coalesce the same pending request', () async {
    final checkout = CheckoutAttempt<String>(), pending = Completer<String>();
    var sends = 0;
    Future<String> send(String _, String _, DateTime _) {
      sends++;
      return pending.future;
    }

    final a = checkout.submit('first basket', send);
    final b = checkout.submit('second basket', send);
    expect(identical(a, b), isTrue);
    expect(sends, 1);
    pending.complete('one-order');
    expect(await a, await b);
  });

  test(
    'confirmed rollback releases checkout, but an identity conflict does not',
    () async {
      for (final code in ['P0001', 'PT409']) {
        final checkout = CheckoutAttempt<String>();
        await expectLater(
          checkout.submit('basket', (_, _, _) async {
            throw PostgrestException(message: 'rejected', code: code);
          }),
          throwsA(isA<PostgrestException>()),
        );
        expect(checkout.snapshot, code == 'P0001' ? null : 'basket');
      }
    },
  );

  test(
    'a previous session completion cannot corrupt a new checkout attempt',
    () async {
      final checkout = CheckoutAttempt<String>(), old = Completer<String>();
      final first = checkout.submit('old user', (_, _, _) => old.future);
      checkout.reset();
      expect(
        await checkout.submit('new user', (_, _, _) async => 'new-order'),
        'new-order',
      );
      old.complete('old-order');
      await first;
      expect(checkout.snapshot, 'new user');
      expect(
        await checkout.submit(
          'ignored',
          (_, _, _) async => fail('already confirmed'),
        ),
        'new-order',
      );
    },
  );

  test('stale demo product edits cannot restore checkout stock', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);
    controller.loginDemo(isAdmin: true);
    controller.adminUpdateOrderPricing(
      minimumOrderPaise: 0,
      deliveryChargePaise: 0,
      freeDeliveryThresholdPaise: 0,
    );
    final before = container
        .read(storeProvider)
        .products
        .firstWhere((p) => p.isAvailable);
    controller.addToCart(before.id);
    final order = controller.placeOrder();
    final after = container.read(storeProvider).productById(before.id)!;
    expect(after.revision, before.revision + 1);
    expect(after.stockQuantity, before.stockQuantity - 1);
    expect(
      () => controller.adminSaveProduct(before.copyWith(pricePaise: 9000)),
      throwsA(isA<StoreValidationException>()),
    );
    controller.cancelOrder(order);
    expect(
      container.read(storeProvider).productById(before.id)!.revision,
      before.revision + 2,
    );
    expect(
      container.read(storeProvider).productById(before.id)!.stockQuantity,
      before.stockQuantity,
    );
  });

  test(
    'confirmation removes only submitted cart quantities and ignores another user',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(storeProvider.notifier);
      controller.loginDemo();
      final products = container
          .read(storeProvider)
          .products
          .where((p) => p.stockQuantity > 2 && p.isAvailable)
          .take(2)
          .toList();
      controller.addToCart(products[0].id);
      final submitted = container.read(storeProvider).cartQuantities;
      controller.addToCart(products[0].id);
      controller.addToCart(products[1].id);
      controller.finishRemoteCheckout(
        'wrong-user-order',
        submittedCart: submitted,
        customerId: 'someone-else',
      );
      expect(container.read(storeProvider).cartCount, 3);
      controller.finishRemoteCheckout(
        'confirmed',
        submittedCart: submitted,
        customerId: 'demo-customer',
      );
      expect(container.read(storeProvider).cartQuantities, {
        products[0].id: 1,
        products[1].id: 1,
      });
      expect(container.read(storeProvider).lastOrderId, 'confirmed');
      controller.finishRemoteCheckout(
        'confirmed',
        submittedCart: submitted,
        customerId: 'demo-customer',
      );
      expect(container.read(storeProvider).cartCount, 2);
    },
  );

  test(
    'out-of-order refreshes do not regress revisions or reset delivery selections',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(storeProvider.notifier);
      controller.loginDemo(isAdmin: true);
      controller.setFulfilment(FulfilmentType.delivery);
      final original = container.read(storeProvider);
      RemoteStoreBundle bundle(
        int sequence,
        int revision, {
        bool admin = true,
      }) => RemoteStoreBundle(
        profile: original.profile!,
        categories: original.categories,
        products: original.products
            .map(
              (p) => p.copyWith(
                revision: revision,
                billingName: admin ? 'STAFF ONLY' : '',
              ),
            )
            .toList(),
        addresses: original.addresses,
        orders: original.orders,
        offers: original.offers,
        pickupSlots: original.pickupSlots,
        deliverySlots: original.deliverySlots,
        isAdmin: admin,
        serviceablePincodes: original.serviceablePincodes,
        minimumOrderPaise: original.minimumOrderPaise,
        baseDeliveryChargePaise: original.baseDeliveryChargePaise,
        freeDeliveryThresholdPaise: original.freeDeliveryThresholdPaise,
        pickupEnabled: true,
        deliveryEnabled: true,
        cashOnDeliveryEnabled: true,
        loadSequence: sequence,
      );
      controller.hydrateRemoteBundle(bundle(2, 5));
      controller.hydrateRemoteBundle(bundle(1, 1));
      expect(container.read(storeProvider).products.first.revision, 5);
      // A newer request may still contain a product read before another mutation.
      controller.hydrateRemoteBundle(bundle(3, 4));
      final refreshed = container.read(storeProvider);
      expect(refreshed.products.first.revision, 5);
      expect(refreshed.fulfilmentType, FulfilmentType.delivery);
      expect(refreshed.selectedSlotLabel, original.selectedSlotLabel);
      expect(refreshed.selectedAddressId, original.selectedAddressId);
      controller.hydrateRemoteBundle(bundle(4, 4, admin: false));
      expect(container.read(storeProvider).isAdminAccount, false);
      // Revision regression protection must not retain private staff fields
      // after the same user's MFA/admin privileges are removed.
      expect(container.read(storeProvider).products.first.billingName, '');
    },
  );

  test(
    'unavailable stock stays visible to admin without becoming purchasable',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final product = container
          .read(storeProvider)
          .products
          .firstWhere((p) => p.isAvailable)
          .copyWith(available: false, revision: 12);
      expect(product.stockQuantity, greaterThan(0));
      expect(product.isAvailable, isFalse);
      expect(product.copyWith(name: 'Edited name').revision, 12);
      expect(product.copyWith(name: 'Edited name').available, isFalse);
    },
  );

  testWidgets(
    'a confirmed order still shows success when detail refresh failed',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(storeProvider.notifier).loginDemo();
      container
          .read(storeProvider.notifier)
          .finishRemoteCheckout('confirmed-id');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderConfirmationScreen(orderId: 'confirmed-id'),
          ),
        ),
      );
      expect(find.text('Order received'), findsOneWidget);
      expect(find.text('Order not found'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
