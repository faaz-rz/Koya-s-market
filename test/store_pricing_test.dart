import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/checkout/models/checkout_models.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  test('admin delivery pricing drives the customer checkout total', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);

    expect(
      () => controller.adminUpdateDeliveryPricing(
        deliveryChargePaise: 0,
        freeDeliveryThresholdPaise: 50000,
      ),
      throwsA(isA<StoreValidationException>()),
    );

    controller.loginDemo(email: 'staff@koyas.in', isAdmin: true);
    final product = container
        .read(storeProvider)
        .products
        .firstWhere((product) => product.isAvailable);
    controller.addToCart(product.id);
    controller.setFulfilment(FulfilmentType.delivery);
    final subtotal = container.read(storeProvider).subtotalPaise;

    controller.adminUpdateDeliveryPricing(
      deliveryChargePaise: 7500,
      freeDeliveryThresholdPaise: subtotal + 1,
    );
    expect(container.read(storeProvider).deliveryChargePaise, 7500);
    expect(container.read(storeProvider).totalPaise, subtotal + 7500);

    controller.adminUpdateDeliveryPricing(
      deliveryChargePaise: 7500,
      freeDeliveryThresholdPaise: subtotal,
    );
    expect(container.read(storeProvider).deliveryChargePaise, 0);

    controller.adminUpdateDeliveryPricing(
      deliveryChargePaise: 0,
      freeDeliveryThresholdPaise: subtotal + 1,
    );
    expect(container.read(storeProvider).deliveryChargePaise, 0);
    expect(container.read(storeProvider).totalPaise, subtotal);
  });
}
