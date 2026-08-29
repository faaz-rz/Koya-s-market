import '../../checkout/models/checkout_models.dart';
import '../../offers/models/store_offer.dart';
import 'generated_product_catalog.dart';

abstract final class DemoStoreData {
  static const minimumDemoStockQuantity = 25;

  static const categories = GeneratedProductCatalog.categories;
  static final products = GeneratedProductCatalog.products
      .map(
        (product) => product.stockQuantity < minimumDemoStockQuantity
            ? product.copyWith(stockQuantity: minimumDemoStockQuantity)
            : product,
      )
      .toList(growable: false);

  static final offers = [
    const StoreOffer(
      id: 'demo-cart-10',
      code: 'CART10',
      title: '10% off your basket',
      description: 'Save 10% on orders of ₹500 or more.',
      minimumSubtotalPaise: 50000,
      discountType: OfferDiscountType.percentage,
      discountValue: 10,
      maximumDiscountPaise: 15000,
      perCustomerLimit: 5,
      active: true,
    ),
    StoreOffer(
      id: 'demo-free-gift',
      code: 'FREEGIFT',
      title: 'Free grocery gift',
      description: 'Get a free product when your basket reaches ₹300.',
      minimumSubtotalPaise: 30000,
      freeProductId: products.first.id,
      freeQuantity: 1,
      perCustomerLimit: 2,
      active: true,
    ),
  ];

  static const addresses = [
    CustomerAddress(
      id: 'home-1',
      label: 'Home',
      recipientName: 'Ezlin',
      phone: '+91 98765 43210',
      line1: '12, Lake View Colony, Banjara Hills',
      city: 'Hyderabad',
      pincode: '500034',
      instructions: 'Call when you reach the main gate.',
      isDefault: true,
    ),
  ];

  static const pickupSlots = [FulfilmentSlot(id: 'p1', label: 'Store hours')];

  static const deliverySlots = [
    FulfilmentSlot(id: 'd1', label: '10:00 AM – 1:00 PM'),
    FulfilmentSlot(id: 'd2', label: '2:00 PM – 5:00 PM'),
    FulfilmentSlot(id: 'd3', label: '6:00 PM – 9:00 PM'),
  ];

  static const serviceablePincodes = {
    '500001',
    '500004',
    '500028',
    '500033',
    '500034',
    '500081',
  };
}
