import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:koyas_supermarket/core/theme/appearance_provider.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/core/widgets/appearance_selector.dart';
import 'package:koyas_supermarket/features/products/widgets/product_visual.dart';
import 'package:koyas_supermarket/features/store/data/generated_product_catalog.dart';
import 'package:koyas_supermarket/features/checkout/models/delivery_pin.dart';
import 'package:koyas_supermarket/features/checkout/services/delivery_address_lookup.dart';
import 'package:koyas_supermarket/features/checkout/widgets/delivery_location_picker.dart';

class NativeAppearancePreview extends ConsumerWidget {
  const NativeAppearancePreview({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ref.watch(appearanceProvider),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('Android photo check'),
        actions: const [AppearanceButton()],
      ),
      body: GridView.count(
        crossAxisCount: 2,
        children: [
          for (final product
              in GeneratedProductCatalog.products
                  .where((p) => p.imageAsset.isNotEmpty)
                  .take(6))
            ProductVisual(product: product.copyWith(clearImage: true)),
        ],
      ),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native photographs decode and manual appearance survives fresh storage reads',
    (tester) async {
      expect(Platform.isAndroid, true);
      final storage = DeviceAppearanceStorage();
      final original = await storage.read();
      try {
        await tester.pumpWidget(
          const ProviderScope(child: NativeAppearancePreview()),
        );
        await tester.pumpAndSettle();
        for (var attempt = 0; attempt < 50; attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (tester.allRenderObjects
                  .whereType<RenderImage>()
                  .where((image) => image.image != null)
                  .length >=
              6) {
            break;
          }
        }
        final images = tester.allRenderObjects.whereType<RenderImage>().where(
          (image) => image.image != null,
        );
        expect(images.length, greaterThanOrEqualTo(6));
        await tester.tap(find.byTooltip('Change appearance'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('appearance-dark')));
        await tester.pumpAndSettle();
        expect(await DeviceAppearanceStorage().read(), ThemeMode.dark);
        expect(
          Theme.of(tester.element(find.byType(ProductVisual).first)).brightness,
          Brightness.dark,
        );
        await tester.tap(find.byTooltip('Change appearance'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('appearance-light')));
        await tester.pumpAndSettle();
        expect(await DeviceAppearanceStorage().read(), ThemeMode.light);
        expect(
          Theme.of(tester.element(find.byType(ProductVisual).first)).brightness,
          Brightness.light,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await storage.write(original);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'native geocoder resolves Hyderabad city and PIN and the real map opens',
    (tester) async {
      final pin = DeliveryPin(
        latitude: 17.386,
        longitude: 78.419,
        accuracyMeters: 12,
        capturedAt: DateTime.now(),
      );
      final address = await DeliveryAddressLookup().resolve(pin);
      expect(address, isNotNull);
      expect(address!.city, isNotEmpty);
      expect(address.pincode, matches(RegExp(r'^\d{6}$')));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: DeliveryLocationPickerSheet(initialPin: pin)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('delivery-location-map')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
