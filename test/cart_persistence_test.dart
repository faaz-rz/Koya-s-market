import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/cart/data/saved_cart_storage.dart';
import 'package:koyas_supermarket/features/cart/providers/cart_persistence.dart';
import 'package:koyas_supermarket/features/profile/models/customer_profile.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

class CartMemory extends SavedCartStorage {
  final carts = <String, Map<String, int>>{};
  final writes = <String>[];
  Completer<Map<String, int>>? pending;
  bool fail = false;
  @override
  Future<Map<String, int>> read(String user) async =>
      pending?.future ?? Map.of(carts[user] ?? {});
  @override
  Future<void> write(String user, Map<String, int> items) async {
    if (fail) throw StateError('storage unavailable');
    carts[user] = Map.of(items);
    writes.add(user);
  }

  @override
  Future<void> remove(String user) async => carts.remove(user);
}

class CartTestStore extends StoreController {
  void signIn(String user) {
    state = state.copyWith(
      isAuthenticated: true,
      isAdminAccount: false,
      cartQuantities: {},
      profile: CustomerProfile(
        id: user,
        name: 'Test',
        email: '$user@example.test',
        phone: '',
      ),
    );
  }
}

void main() {
  late CartMemory storage;
  late ProviderContainer c;
  late CartPersistence persistence;
  setUp(() {
    storage = CartMemory();
    c = ProviderContainer(
      overrides: [
        savedCartStorageProvider.overrideWithValue(storage),
        storeProvider.overrideWith(CartTestStore.new),
      ],
    );
    persistence = c.read(cartPersistenceProvider);
  });
  tearDown(() => c.dispose());
  test(
    'cart restores after reopen and logout/login; empty logout never overwrites the saved account cart',
    () async {
      final controller = c.read(storeProvider.notifier) as CartTestStore;
      controller.signIn('alice');
      await persistence.restored;
      final product = c
          .read(storeProvider)
          .products
          .firstWhere((p) => p.isAvailable);
      controller.addToCart(product.id);
      controller.addToCart(product.id);
      await persistence.flushed;
      controller.logout();
      await persistence.flushed;
      expect(c.read(storeProvider).cartQuantities, isEmpty);
      expect(storage.carts['alice'], {product.id: 2});
      controller.signIn('alice');
      await persistence.restored;
      expect(c.read(storeProvider).cartQuantities, {product.id: 2});
      c.dispose();
      c = ProviderContainer(
        overrides: [
          savedCartStorageProvider.overrideWithValue(storage),
          storeProvider.overrideWith(CartTestStore.new),
        ],
      );
      persistence = c.read(cartPersistenceProvider);
      (c.read(storeProvider.notifier) as CartTestStore).signIn('alice');
      await persistence.restored;
      expect(c.read(storeProvider).cartQuantities, {product.id: 2});
    },
  );
  test(
    'different accounts remain isolated; a late restore after logout cannot insert the previous basket',
    () async {
      final controller = c.read(storeProvider.notifier) as CartTestStore;
      final product = c
          .read(storeProvider)
          .products
          .firstWhere((p) => p.isAvailable);
      storage.carts['alice'] = {product.id: 3};
      storage.pending = Completer();
      controller.signIn('alice');
      await Future<void>.delayed(Duration.zero);
      final previousRead = persistence.restored;
      controller.logout();
      storage.pending!.complete({product.id: 3});
      await previousRead;
      storage.pending = null;
      expect(c.read(storeProvider).cartQuantities, isEmpty);
      controller.signIn('bob');
      await persistence.restored;
      expect(c.read(storeProvider).cartQuantities, isEmpty);
      controller.addToCart(product.id);
      await persistence.flushed;
      controller.logout();
      controller.signIn('alice');
      await persistence.restored;
      expect(c.read(storeProvider).cartQuantities, {product.id: 3});
      expect(storage.carts['bob'], {product.id: 1});
    },
  );
  test(
    'edits while restoring merge with saved quantities, and confirmed checkout removes only submitted quantities',
    () async {
      final controller = c.read(storeProvider.notifier) as CartTestStore;
      final product = c
          .read(storeProvider)
          .products
          .firstWhere((p) => p.isAvailable);
      storage.pending = Completer();
      controller.signIn('alice');
      await Future<void>.delayed(Duration.zero);
      controller.addToCart(product.id);
      storage.pending!.complete({product.id: 2});
      await persistence.restored;
      expect(c.read(storeProvider).cartQuantities, {product.id: 3});
      controller.finishRemoteCheckout(
        'confirmed-order',
        submittedCart: {product.id: 2},
        customerId: 'alice',
      );
      await persistence.flushed;
      expect(storage.carts['alice'], {product.id: 1});
      controller.finishRemoteCheckout(
        'another-confirmed-order',
        submittedCart: {product.id: 1},
        customerId: 'alice',
      );
      await persistence.flushed;
      expect(storage.carts['alice'], isEmpty);
    },
  );
  test(
    'saved prices are never trusted; corrupt input, absent catalogue items, and failed storage remain safe',
    () async {
      expect(EncryptedCartStorage.decode('bad'), isEmpty);
      expect(
        EncryptedCartStorage.decode(
          jsonEncode({
            'version': 1,
            'items': {'x': -1, 'y': 1000000, 'z': '2'},
          }),
        ),
        isEmpty,
      );
      final controller = c.read(storeProvider.notifier) as CartTestStore;
      storage.carts['alice'] = {'removed-product': 4};
      controller.signIn('alice');
      await persistence.restored;
      expect(c.read(storeProvider).cartQuantities, isEmpty);
      expect(c.read(savedCartStatusProvider).message, contains('no longer'));
      storage.fail = true;
      final product = c
          .read(storeProvider)
          .products
          .firstWhere((p) => p.isAvailable);
      controller.addToCart(product.id);
      await persistence.flushed;
      expect(
        c.read(savedCartStatusProvider).message,
        contains('could not be saved'),
      );
      expect(c.read(storeProvider).cartQuantities, {product.id: 1});
    },
  );
  test(
    'account deletion removes its saved cart and cannot erase a different account',
    () async {
      final controller = c.read(storeProvider.notifier) as CartTestStore;
      final product = c
          .read(storeProvider)
          .products
          .firstWhere((p) => p.isAvailable);
      storage.carts['alice'] = {product.id: 2};
      storage.carts['bob'] = {product.id: 1};
      controller.signIn('alice');
      await persistence.restored;
      await persistence.deleteForAccount('alice');
      controller.logout();
      expect(storage.carts.containsKey('alice'), false);
      expect(storage.carts['bob'], {product.id: 1});
    },
  );
}
