import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:koyas_supermarket/features/cart/data/saved_cart_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android encrypted carts survive new instances and stay isolated',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      final first = EncryptedCartStorage();
      const alice = 'qa-encrypted-cart-alice';
      const bob = 'qa-encrypted-cart-bob';
      try {
        await first.write(alice, {'qa-product-a': 2, 'qa-product-b': 15});
        await first.write(bob, {'qa-product-a': 1});
        final reopened = EncryptedCartStorage();
        expect(await reopened.read(alice), {
          'qa-product-a': 2,
          'qa-product-b': 15,
        });
        expect(await reopened.read(bob), {'qa-product-a': 1});
        await reopened.remove(alice);
        expect(await first.read(alice), isEmpty);
        expect(await first.read(bob), {'qa-product-a': 1});
      } finally {
        await first.remove(alice);
        await first.remove(bob);
      }
    },
  );
}
