import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/offers/models/store_offer.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  test('flat and percentage offers calculate bounded discounts', () {
    const flat = StoreOffer(
      id: 'flat',
      code: 'FLAT100',
      title: 'Flat discount',
      minimumSubtotalPaise: 0,
      discountType: OfferDiscountType.flat,
      discountValue: 10000,
      active: true,
    );
    const percent = StoreOffer(
      id: 'percent',
      code: 'SAVE20',
      title: 'Percentage discount',
      minimumSubtotalPaise: 0,
      discountType: OfferDiscountType.percentage,
      discountValue: 20,
      maximumDiscountPaise: 15000,
      active: true,
    );

    expect(flat.discountFor(7500), 7500);
    expect(flat.discountFor(50000), 10000);
    expect(percent.discountFor(50000), 10000);
    expect(percent.discountFor(100000), 15000);
  });

  test('minimum basket is enforced before an offer can be applied', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);
    controller.loginDemo(email: 'staff@koyas.in', isAdmin: true);
    final product = container
        .read(storeProvider)
        .products
        .firstWhere((item) => item.isAvailable);
    controller.addToCart(product.id);
    final subtotal = container.read(storeProvider).subtotalPaise;
    controller.adminSaveOffer(
      StoreOffer(
        id: 'minimum-test',
        code: 'MINIMUM',
        title: 'Minimum basket test',
        minimumSubtotalPaise: subtotal + 1,
        discountType: OfferDiscountType.flat,
        discountValue: 100,
        active: true,
      ),
    );

    expect(
      () => controller.applyOffer('minimum'),
      throwsA(isA<StoreValidationException>()),
    );
  });

  test('combined discount and free-product offer is snapshotted in order', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);
    controller.loginDemo(email: 'staff@koyas.in', isAdmin: true);
    final products = container
        .read(storeProvider)
        .products
        .where((item) => item.isAvailable)
        .take(2)
        .toList(growable: false);
    final purchased = products.first;
    final freeProduct = products.last;
    controller.addToCart(purchased.id);
    final subtotal = container.read(storeProvider).subtotalPaise;
    final freeStock = freeProduct.stockQuantity;
    controller.adminSaveOffer(
      StoreOffer(
        id: 'combined-test',
        code: 'COMBINED',
        title: 'Discount plus gift',
        minimumSubtotalPaise: subtotal,
        discountType: OfferDiscountType.flat,
        discountValue: 500,
        freeProductId: freeProduct.id,
        freeQuantity: 2,
        perCustomerLimit: 2,
        active: true,
      ),
    );

    controller.applyOffer('combined');
    final beforeOrder = container.read(storeProvider);
    expect(beforeOrder.offerDiscountPaise, 500.clamp(0, subtotal));
    expect(beforeOrder.freeOfferProduct?.id, freeProduct.id);
    final orderId = controller.placeOrder();
    final afterOrder = container.read(storeProvider);
    final order = afterOrder.orders.firstWhere((item) => item.id == orderId);

    expect(order.offerCode, 'COMBINED');
    expect(order.offerTitle, 'Discount plus gift');
    expect(order.offerDiscountPaise, 500.clamp(0, subtotal));
    expect(
      order.items.singleWhere((item) => item.isFreeOfferItem).productId,
      freeProduct.id,
    );
    expect(order.items.singleWhere((item) => item.isFreeOfferItem).quantity, 2);
    expect(
      afterOrder.productById(freeProduct.id)?.stockQuantity,
      freeStock - 2,
    );
    expect(afterOrder.selectedOfferCode, isNull);
  });
}
